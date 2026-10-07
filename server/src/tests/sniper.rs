//! Sniper Rifle and Ranged Sweeper: seeded tick tests of the far precision
//! gun beside the Railgun, the marksman's glint and hold, ducking a sill and
//! the shared campaign wire.
use crate::encounters::enemy::attack_timing;
use crate::maps::{AuthoredMap, RuntimeMap};
use crate::protocol::{
    Action, AmmoPool, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, LookAt, Role,
    ShotImpact, WeaponType,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::json;
use uuid::Uuid;

const FACING_SOUTH: f32 = 4.712389;
const RANGE: &[u8] = include_bytes!("../../maps/test/sniper-range.json");

/// A shooter at the south end and one dormant target `distance` metres north.
fn lane(kind: &str, distance: f32) -> (GameSession, Uuid, Uuid) {
    let doc = json!({
        "version":1,"map_id":1000,"name":"Sniper lane","half_extent":64,
        "ground":"concrete","equipment":"discovery","solids":[],
        "spawns":[{"id":"entry","feet":[0,0,-50],"yaw":1.5707964}],
        "landmarks":[{"id":"far","feet":[0,0,50]}],
        "encounters":[{
            "id":"far_lane","regions":[{"min":[-2,0,60],"max":[2,2,62]}],
            "enemies":[{"id":"target","kind":kind,"feet":[0,0,-50.0 + distance],"yaw":FACING_SOUTH}]
        }]
    });
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let id = Uuid::from_u128(700);
    session.state.add_player(id, "Marksman".into(), Role::Human);
    advance(&mut session, 1);
    place(&mut session, id, 0.0, 0.0, -50.0);
    let target = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    (session, id, target)
}

/// A Ranged Sweeper `distance` metres north of an open visitor on Standard.
/// `mission::difficulty_tests` covers every tier's tell in a mission room.
fn marksman(distance: f32, yaw: f32) -> (GameSession, Uuid, Uuid) {
    let doc = json!({
        "version":1,"map_id":1000,"name":"Marksman lane","half_extent":64,
        "ground":"concrete","equipment":"discovery","solids":[],
        "spawns":[{"id":"entry","feet":[0,0,-40],"yaw":1.5707964}],
        "landmarks":[{"id":"far","feet":[0,0,50]}],
        "encounters":[{
            "id":"rim","regions":[{"min":[-64,0,-64],"max":[64,2,64]}],
            "enemies":[{"id":"marksman","kind":"ranged_sweeper","feet":[0,0,-40.0 + distance],"yaw":yaw}]
        }]
    });
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let id = Uuid::from_u128(701);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    advance(&mut session, 1);
    place(&mut session, id, 0.0, 0.0, -40.0);
    let guard = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    (session, id, guard)
}

fn range_session(seed: u64) -> (GameSession, Uuid, Uuid) {
    let map = AuthoredMap::read(RANGE).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(seed);
    let id = Uuid::from_u128(702);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    advance(&mut session, 1);
    let guard = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    (session, id, guard)
}

fn advance(session: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        session.tick_messages(0.05);
    }
}

fn place(session: &mut GameSession, id: Uuid, x: f32, floor: f32, z: f32) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.x = x;
    player.y = PLAYER_FLOOR_Y + floor;
    player.z = z;
    player.vy = 0.0;
}

fn body(session: &GameSession, id: Uuid) -> &crate::sim::Player {
    session.state.players.iter().find(|p| p.id == id).unwrap()
}

fn identity(session: &GameSession, id: Uuid) -> (EnemyKind, EnemyPhase, u64, u64) {
    match body(session, id).campaign.unwrap() {
        CampaignActor::Union {
            kind,
            phase,
            phase_started,
            phase_ends,
            ..
        } => (kind, phase, phase_started, phase_ends),
        _ => panic!("expected a Union actor"),
    }
}

fn cells(session: &GameSession, id: Uuid) -> u16 {
    let player = body(session, id);
    player
        .inventory
        .state(player.id, player.weapon, session.state.tick)
        .unwrap()
        .ammo(AmmoPool::Cells)
}

fn trace(shot: &crate::protocol::ShotResult) -> &crate::protocol::ShotTrace {
    shot.trace
        .as_ref()
        .expect("current servers send shot evidence")
}

fn phase(session: &GameSession, id: Uuid) -> EnemyPhase {
    identity(session, id).1
}

fn shots_from(session: &GameSession, shooter: Uuid) -> Vec<crate::protocol::ShotResult> {
    session
        .state
        .shot_results
        .iter()
        .filter(|shot| shot.shooter_id == shooter)
        .cloned()
        .collect()
}

fn until(session: &mut GameSession, guard: Uuid, wanted: EnemyPhase, limit: usize) {
    for _ in 0..limit {
        if phase(session, guard) == wanted {
            return;
        }
        advance(session, 1);
    }
    panic!("guard never reached {wanted:?}");
}

/// Equip, aim with an explicit absolute yaw and pitch, and fire one tick.
fn fire_at_angle(
    session: &mut GameSession,
    shooter: Uuid,
    weapon: WeaponType,
    yaw: f32,
    pitch: f32,
) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == shooter)
        .unwrap();
    player.inventory.grant_weapon(weapon);
    player.weapon = weapon;
    player.fire_cooldown = 0;
    session.state.set_action(
        shooter,
        Action {
            fire: true,
            yaw: Some(yaw),
            pitch: Some(pitch),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    session.state.set_action(shooter, Action::default());
}

fn fire_at(session: &mut GameSession, shooter: Uuid, target: Uuid, weapon: WeaponType) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == shooter)
        .unwrap();
    player.inventory.grant_weapon(weapon);
    player.weapon = weapon;
    player.fire_cooldown = 0;
    session.state.set_action(
        shooter,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(target),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    session.state.set_action(shooter, Action::default());
}

/// Pitch from the shooter's eye to the chest of a standing fighter ahead.
fn level_pitch(distance: f32) -> f32 {
    let rise = crate::combat::aim_height(None) - crate::movement::EYE_HEIGHT;
    rise.atan2(distance)
}

#[test]
fn sniper_table_owns_far_precision_without_reusing_rail_numbers() {
    let sniper = WeaponType::Sniper;
    let rail = WeaponType::Rail;
    assert_eq!(sniper.ammo_pool(), Some(AmmoPool::Cells));
    assert_eq!(sniper.ammo_pool(), rail.ammo_pool());
    assert_ne!(sniper.damage(), rail.damage(), "never Rail damage");
    assert!(sniper.damage() > WeaponType::Flechette.damage());
    assert!(sniper.cooldown_ticks() > rail.cooldown_ticks());
    assert!(sniper.spread_radians() < rail.spread_radians());
    assert!(sniper.range_units() > rail.range_units());
    assert_eq!(sniper.pellets(), 1);
    assert_eq!(sniper.pickup_rounds(), 8);
    assert_eq!(sniper.name(), "Sniper");
    assert!(!WeaponType::ARCADE.contains(&sniper));
    assert_eq!(WeaponType::ALL[sniper.index()], sniper);
    // Every ray stays inside a body's radius out to the full reach.
    assert!(sniper.spread_radians().tan() * sniper.range_units() < crate::movement::RADIUS);
    // The Rail's cone already leaves a centred body before its own reach.
    assert!(rail.spread_radians().tan() * 55.0 > crate::movement::RADIUS);
    assert_eq!(serde_json::to_value(sniper).unwrap(), json!("sniper"));
    assert_eq!(
        serde_json::from_value::<WeaponType>(json!("sniper")).unwrap(),
        sniper
    );
    assert!(serde_json::from_value::<WeaponType>(json!("Sniper")).is_err());
}

#[test]
fn a_tight_far_sniper_hit_lands_seventy_with_its_own_trace_and_one_cell() {
    let (mut session, id, target) = lane("sweeper", 75.0);
    assert_eq!(body(&session, target).hp, 80);
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .grant_weapon(WeaponType::Sniper);
    assert_eq!(cells(&session, id), 8);
    fire_at_angle(
        &mut session,
        id,
        WeaponType::Sniper,
        std::f32::consts::FRAC_PI_2,
        level_pitch(75.0),
    );
    let shots = shots_from(&session, id);
    assert_eq!(shots.len(), 1);
    let shot = &shots[0];
    assert_eq!(trace(shot).weapon, WeaponType::Sniper);
    assert_ne!(trace(shot).weapon, WeaponType::Rail, "no rail beam source");
    assert_eq!(shot.target_id, Some(target));
    assert_eq!(shot.damage, 70);
    assert!(matches!(trace(shot).impact, ShotImpact::Fighter { .. }));
    assert_eq!(body(&session, target).hp, 10, "a Sweeper needs two");
    // One Cell spent; the helper's second grant added another eight.
    assert_eq!(cells(&session, id), 8 + 8 - 1);
}

#[test]
fn held_fire_paces_the_sniper_slower_than_the_rail() {
    for weapon in [WeaponType::Sniper, WeaponType::Rail] {
        let (mut session, id, _) = lane("heavy_sweeper", 30.0);
        {
            let player = session
                .state
                .players
                .iter_mut()
                .find(|p| p.id == id)
                .unwrap();
            player.inventory.grant_weapon(weapon);
            player.inventory.grant_ammo(AmmoPool::Cells, 100);
            player.weapon = weapon;
            player.fire_cooldown = 0;
        }
        let mut fired = Vec::new();
        for _ in 0..70 {
            session.state.set_action(
                id,
                Action {
                    fire: true,
                    yaw: Some(std::f32::consts::FRAC_PI_2 + 0.5),
                    ..Default::default()
                },
            );
            session.state.tick(0.05);
            if !shots_from(&session, id).is_empty() {
                fired.push(session.state.tick);
            }
        }
        assert!(fired.len() >= 2, "{weapon:?} fired {fired:?}");
        assert_eq!(
            fired[1] - fired[0],
            u64::from(weapon.cooldown_ticks()),
            "{weapon:?}"
        );
    }
}

#[test]
fn a_rail_shot_reaches_nothing_beyond_sixty_metres_where_the_sniper_hits() {
    let (mut session, id, target) = lane("sweeper", 75.0);
    fire_at_angle(
        &mut session,
        id,
        WeaponType::Rail,
        std::f32::consts::FRAC_PI_2,
        level_pitch(75.0),
    );
    let shot = shots_from(&session, id).pop().unwrap();
    assert_eq!(trace(&shot).weapon, WeaponType::Rail);
    assert_eq!(shot.target_id, None);
    assert_eq!(shot.damage, 0);
    assert!(matches!(trace(&shot).impact, ShotImpact::Range));
    let origin = trace(&shot).origin;
    let travelled = (0..3)
        .map(|i| (trace(&shot).end[i] - origin[i]).powi(2))
        .sum::<f32>()
        .sqrt();
    assert!((travelled - 60.0).abs() < 0.01, "rail ends at its reach");
    assert_eq!(body(&session, target).hp, 80);
    advance(&mut session, 25);
    fire_at_angle(
        &mut session,
        id,
        WeaponType::Sniper,
        std::f32::consts::FRAC_PI_2,
        level_pitch(75.0),
    );
    assert_eq!(body(&session, target).hp, 10);
}

#[test]
fn aim_outside_the_sniper_cone_misses_a_far_body() {
    let (mut session, id, target) = lane("sweeper", 75.0);
    // The body subtends 0.5 / 75 rad; the cone adds 0.004. Aim beyond both.
    let offset = WeaponType::Sniper.spread_radians() + crate::movement::RADIUS / 75.0 + 0.002;
    for seed in 0..12 {
        session.state.seed(seed);
        advance(&mut session, 40);
        fire_at_angle(
            &mut session,
            id,
            WeaponType::Sniper,
            std::f32::consts::FRAC_PI_2 + offset,
            level_pitch(75.0),
        );
        let shot = shots_from(&session, id).pop().unwrap();
        assert_eq!(shot.target_id, None, "seed {seed}");
    }
    assert_eq!(body(&session, target).hp, 80);
}

#[test]
fn at_fifty_five_metres_the_rail_cone_misses_where_the_sniper_never_does() {
    let mut rail_hits = 0;
    let mut sniper_hits = 0;
    const VOLLEY: usize = 60;
    for (weapon, hits) in [
        (WeaponType::Rail, &mut rail_hits),
        (WeaponType::Sniper, &mut sniper_hits),
    ] {
        let (mut session, id, target) = lane("heavy_sweeper", 55.0);
        session.state.seed(9);
        for _ in 0..VOLLEY {
            session
                .state
                .players
                .iter_mut()
                .find(|p| p.id == target)
                .unwrap()
                .hp = 1000;
            fire_at_angle(
                &mut session,
                id,
                weapon,
                std::f32::consts::FRAC_PI_2,
                level_pitch(55.0),
            );
            if shots_from(&session, id)
                .pop()
                .is_some_and(|shot| shot.target_id == Some(target))
            {
                *hits += 1;
            }
            // The armored target never walks out of its lane in one tick.
            place(&mut session, target, 0.0, 0.0, 5.0);
        }
    }
    assert_eq!(
        sniper_hits, VOLLEY,
        "the Sniper cone stays on a centred body"
    );
    assert!(
        rail_hits < VOLLEY,
        "the Rail cone leaves the body at 55 m: {rail_hits}/{VOLLEY}"
    );
}

#[test]
fn a_dry_sniper_does_not_fire_and_counts_the_trigger() {
    let (mut session, id, target) = lane("sweeper", 40.0);
    {
        let player = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap();
        player.inventory.grant_weapon(WeaponType::Sniper);
        while player.inventory.try_fire(WeaponType::Sniper) {}
        player.inventory.release_trigger();
        player.weapon = WeaponType::Sniper;
        player.fire_cooldown = 0;
    }
    let dry_before = body(&session, id).inventory.dry_fire_count();
    session.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(target),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    assert!(shots_from(&session, id).is_empty());
    assert_eq!(body(&session, target).hp, 80);
    assert!(body(&session, id).inventory.dry_fire_count() > dry_before);
}

#[test]
fn the_ranged_sweeper_glints_holds_and_fires_on_the_documented_tick_at_seventy_metres() {
    let mut windups = Vec::new();
    for difficulty in [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ] {
        let (windup, _) = attack_timing(EnemyKind::RangedSweeper, difficulty);
        assert!(windup >= 20, "Severe keeps more than one second of tell");
        windups.push(windup);
    }
    assert!(windups.windows(2).all(|pair| pair[0] > pair[1]));
    {
        let difficulty = CampaignDifficulty::Standard;
        let (windup, recovery) = attack_timing(EnemyKind::RangedSweeper, difficulty);
        let (mut session, id, guard) = marksman(70.0, FACING_SOUTH);
        assert_eq!(body(&session, guard).hp, 70);
        assert_eq!(body(&session, guard).weapon, WeaponType::Sniper);
        session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap()
            .hp = 100;
        until(&mut session, guard, EnemyPhase::Windup, 10);
        let (kind, _, start, end) = identity(&session, guard);
        assert_eq!(kind, EnemyKind::RangedSweeper);
        assert_eq!(end - start, windup, "{difficulty:?}");
        // The glint holds: no shot, no damage, until the last windup tick.
        while session.state.tick < end - 1 {
            advance(&mut session, 1);
            assert!(shots_from(&session, guard).is_empty());
            assert_eq!(body(&session, id).hp, 100);
            assert_eq!(phase(&session, guard), EnemyPhase::Windup);
        }
        advance(&mut session, 1);
        assert_eq!(session.state.tick, end);
        let shot = shots_from(&session, guard)
            .pop()
            .expect("fires on its tick");
        assert_eq!(trace(&shot).weapon, WeaponType::Sniper);
        assert_eq!(shot.target_id, Some(id));
        assert_eq!(shot.damage, 70);
        assert_eq!(body(&session, id).hp, 30);
        until(&mut session, guard, EnemyPhase::Recovery, 3);
        let (_, _, recovery_start, recovery_end) = identity(&session, guard);
        assert_eq!(recovery_end - recovery_start, recovery);
        // The marksman never leaves its platform.
        assert_eq!(
            (body(&session, guard).x, body(&session, guard).z),
            (0.0, 30.0)
        );
    }
}

#[test]
fn dropping_behind_the_sill_cancels_the_glint_without_a_shot() {
    let (mut session, id, guard) = range_session(11);
    assert_eq!(identity(&session, guard).0, EnemyKind::RangedSweeper);
    // Step onto the firing step: the head clears the sill, the body does not.
    place(&mut session, id, 0.0, 0.5, -30.6);
    until(&mut session, guard, EnemyPhase::Windup, 20);
    let (_, _, start, end) = identity(&session, guard);
    let standard = attack_timing(EnemyKind::RangedSweeper, CampaignDifficulty::Standard).0;
    assert_eq!(end - start, standard);
    // React well inside the window: drop off the step behind the sill.
    advance(&mut session, (standard / 2) as usize);
    place(&mut session, id, 0.0, 0.0, -32.2);
    advance(&mut session, 1);
    let (_, current, cancel_start, cancel_end) = identity(&session, guard);
    assert_eq!(current, EnemyPhase::Recovery);
    assert_eq!(cancel_end - cancel_start, 12);
    assert!(cancel_start < end, "cancelled before the shot tick");
    while session.state.tick <= end + 2 {
        advance(&mut session, 1);
        assert!(shots_from(&session, guard).is_empty());
    }
    assert_eq!(body(&session, id).hp, 100);
    // Fully below the sill it never starts another glint.
    for _ in 0..80 {
        advance(&mut session, 1);
        assert_ne!(phase(&session, guard), EnemyPhase::Windup);
    }
}

#[test]
fn a_peeking_head_is_seen_and_rising_first_wins_the_duel() {
    let (mut session, id, guard) = range_session(5);
    place(&mut session, id, 0.0, 0.5, -30.6);
    let solids = session.state.current_arena().solids.clone();
    let guard_eye = {
        let g = body(&session, guard);
        [g.x, g.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT, g.z]
    };
    let centre = [0.0, 0.5 + crate::combat::aim_height(None), -30.6];
    let head = [0.0, 0.5 + crate::movement::EYE_HEIGHT, -30.6];
    assert!(!crate::combat::line_of_sight(guard_eye, centre, &solids));
    assert!(crate::combat::line_of_sight(guard_eye, head, &solids));
    let off_step_head = [0.0, crate::movement::EYE_HEIGHT, -32.2];
    assert!(!crate::combat::line_of_sight(
        guard_eye,
        off_step_head,
        &solids
    ));
    until(&mut session, guard, EnemyPhase::Windup, 20);
    // The participant rises and fires first: one aimed Sniper hit answers it.
    fire_at(&mut session, id, guard, WeaponType::Sniper);
    let shot = shots_from(&session, id).pop().unwrap();
    assert_eq!(shot.target_id, Some(guard));
    assert_eq!(shot.damage, 70);
    assert_eq!(phase(&session, guard), EnemyPhase::Dead);
    advance(&mut session, 40);
    assert!(shots_from(&session, guard).is_empty());
    assert_eq!(body(&session, id).hp, 100);
}

#[test]
fn any_hit_staggers_the_marksman_and_cancels_its_glint() {
    let (mut session, id, guard) = marksman(10.0, FACING_SOUTH);
    until(&mut session, guard, EnemyPhase::Windup, 10);
    let (_, _, _, end) = identity(&session, guard);
    fire_at(&mut session, id, guard, WeaponType::Tack);
    advance(&mut session, 1);
    let (_, current, start, stun_end) = identity(&session, guard);
    assert_eq!(current, EnemyPhase::Hit);
    assert_eq!(stun_end - start, 6);
    while session.state.tick <= end {
        advance(&mut session, 1);
        assert!(shots_from(&session, guard).is_empty());
    }
    assert_eq!(body(&session, id).hp, 100);
}

#[test]
fn the_notice_cone_leaves_a_flank_and_the_flanker_can_close_in() {
    // Facing north, away from the visitor 40 m to its south.
    let (mut session, id, guard) = marksman(40.0, 1.5707964);
    for _ in 0..80 {
        advance(&mut session, 1);
        assert_ne!(phase(&session, guard), EnemyPhase::Windup);
        assert!(shots_from(&session, guard).is_empty());
    }
    // A close Shotgun answer from behind the platform.
    place(&mut session, id, 0.0, 0.0, -2.5);
    fire_at(&mut session, id, guard, WeaponType::Scatter);
    fire_at(&mut session, id, guard, WeaponType::Scatter);
    advance(&mut session, 1);
    assert_eq!(phase(&session, guard), EnemyPhase::Dead);
}

#[test]
fn an_unreached_target_is_tracked_but_never_engaged_beyond_reach() {
    let (mut session, _id, guard) = marksman(89.5, FACING_SOUTH);
    for _ in 0..60 {
        advance(&mut session, 1);
        assert_ne!(phase(&session, guard), EnemyPhase::Windup);
        assert!(shots_from(&session, guard).is_empty());
    }
}

#[test]
fn a_dry_marksman_holds_still_and_harmless() {
    let (mut session, id, guard) = marksman(20.0, FACING_SOUTH);
    {
        let g = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == guard)
            .unwrap();
        while g.inventory.try_fire(WeaponType::Sniper) {}
    }
    for _ in 0..80 {
        advance(&mut session, 1);
        assert!(shots_from(&session, guard).is_empty());
    }
    assert_eq!(body(&session, id).hp, 100);
    assert_eq!(
        (body(&session, guard).x, body(&session, guard).z),
        (0.0, -20.0)
    );
}

#[test]
fn the_range_validates_requires_capability_and_resets_on_party_wipe() {
    let map = AuthoredMap::read(RANGE).unwrap();
    let runtime = RuntimeMap::Authored(map);
    assert!(runtime.requires_sniper_contract());
    for other in [
        include_bytes!("../../maps/test/jammer-range.json").as_slice(),
        include_bytes!("../../maps/test/heavy-turret-range.json").as_slice(),
        include_bytes!("../../maps/m06_port_of_entry.json").as_slice(),
    ] {
        let runtime = RuntimeMap::Authored(AuthoredMap::read(other).unwrap());
        assert!(!runtime.requires_sniper_contract());
    }
    let (mut session, id, guard) = range_session(3);
    let original = (body(&session, guard).hp, body(&session, guard).yaw);
    place(&mut session, id, 0.0, 0.5, -30.6);
    fire_at(&mut session, id, guard, WeaponType::Sniper);
    assert_eq!(phase(&session, guard), EnemyPhase::Dead);
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .hp = 0;
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .respawn_timer = Some(5);
    advance(&mut session, 6);
    let restored = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap();
    assert_ne!(restored.id, guard, "retry places a fresh marksman");
    assert_eq!((restored.hp, restored.yaw), original);
    assert_eq!((restored.x, restored.z), (0.0, 40.0));
    assert!((restored.y - PLAYER_FLOOR_Y - 3.0).abs() < 1e-4);
}

#[test]
fn the_ranged_sweeper_kind_is_strict_on_the_actor_wire() {
    let actor = CampaignActor::Union {
        kind: EnemyKind::RangedSweeper,
        phase: EnemyPhase::Windup,
        phase_started: 10,
        phase_ends: 40,
        seated: false,
    };
    let value = serde_json::to_value(actor).unwrap();
    assert_eq!(value["kind"], "ranged_sweeper");
    assert_eq!(
        serde_json::from_value::<CampaignActor>(value).unwrap(),
        actor
    );
    for near in [
        "ranged",
        "rangedsweeper",
        "sniper_sweeper",
        "Ranged_Sweeper",
    ] {
        assert!(serde_json::from_value::<CampaignActor>(json!({
            "side":"union","kind":near,"phase":"idle","phase_started":0,"phase_ends":0
        }))
        .is_err());
    }
}

#[tokio::test]
async fn the_range_refuses_pre_sniper_readers_and_sends_geometry_before_snapshots() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(crate::maps::AuthoredSource::File(
                std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .join("maps/test/sniper-range.json"),
            )),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = tokio::time::timeout(Duration::from_secs(30), ready_rx)
        .await
        .unwrap()
        .unwrap();
    for version in [
        crate::protocol::M05_GAMEPLAY_VERSION,
        crate::protocol::M06_GAMEPLAY_VERSION,
        crate::protocol::SNIPER_GAMEPLAY_VERSION,
    ] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket
                .send(Message::Text(
                    json!({
                        "type":"hello", "role":role, "name":"ScopeProbe",
                        "gameplay_version":version,
                        "geometry_version":crate::protocol::GEOMETRY_VERSION
                    })
                    .to_string(),
                ))
                .await
                .unwrap();
            tokio::time::timeout(Duration::from_secs(5), async {
                let mut saw_map = false;
                let mut saw_welcome = false;
                loop {
                    let message = socket.next().await.unwrap().unwrap();
                    let Message::Text(text) = message else {
                        continue;
                    };
                    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                    if version < crate::protocol::SNIPER_GAMEPLAY_VERSION {
                        assert_eq!(value["type"], "error", "pre-Sniper reader admitted");
                        assert_eq!(value["code"], "unsupported_gameplay");
                        assert!(value["message"].as_str().unwrap().contains("30"));
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "welcome" => saw_welcome = true,
                        "map_info" => {
                            assert_eq!(value["map_id"], 1013);
                            saw_map = true;
                        }
                        "snapshot" => {
                            assert!(saw_map && saw_welcome, "snapshot overtook geometry");
                            break;
                        }
                        "error" => panic!("current reader rejected: {value}"),
                        _ => {}
                    }
                }
            })
            .await
            .expect("bounded range admission");
            let _ = socket.close(None).await;
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[test]
fn agents_take_the_carried_sniper_for_a_hostile_beyond_their_gun() {
    use crate::inventory::control_action;
    let (mut session, id, target) = lane("sweeper", 75.0);
    {
        let player = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap();
        player.inventory.grant_weapon(WeaponType::Flechette);
        player.weapon = WeaponType::Flechette;
    }
    // Wake the far guard so it reads as a hostile in the snapshot.
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == target)
        .unwrap()
        .hp = 80;
    let snapshot = session.state.snapshot();
    let loadout = |session: &GameSession| {
        let player = body(session, id);
        player
            .inventory
            .state(player.id, player.weapon, session.state.tick)
            .unwrap()
    };
    let without = control_action(id, &snapshot, Some(&loadout(&session)), Action::default());
    assert_ne!(
        without.weapon_swap,
        Some(WeaponType::Sniper),
        "not carried yet"
    );
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .grant_weapon(WeaponType::Sniper);
    let with = control_action(id, &snapshot, Some(&loadout(&session)), Action::default());
    assert_eq!(with.weapon_swap, Some(WeaponType::Sniper));
    assert!(with.fire, "inside the Sniper's reach");
    // An explicit usable request is never overridden.
    let requested = control_action(
        id,
        &snapshot,
        Some(&loadout(&session)),
        Action {
            weapon_swap: Some(WeaponType::Flechette),
            ..Default::default()
        },
    );
    assert_eq!(requested.weapon_swap, None, "already holding the request");
    // A close hostile keeps the held Rifle.
    place(&mut session, target, 0.0, 0.0, -30.0);
    let near = session.state.snapshot();
    let close = control_action(id, &near, Some(&loadout(&session)), Action::default());
    assert_ne!(close.weapon_swap, Some(WeaponType::Sniper));
}
