//! Locational damage (#533): height zones on the shared body cylinder, a
//! multiplier per weapon class, and campaign tables per body kind. Every
//! number here is the table in `docs/plans/locational-damage.md` section 5.

use crate::combat::{band_for, zoned_damage, Band, HEAD_GATE, LEG_GATE};
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, CampaignActor, EnemyKind, EnemyPhase, HitZone, LookAt, Role, ShotResult, WeaponType,
};
use crate::session::GameSession;
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use serde_json::json;
use uuid::Uuid;

/// Height above the feet in the middle of each standing band.
const HEAD: f32 = 1.65;
const TORSO: f32 = 1.15;
const LEGS: f32 = 0.45;
const FACING_SOUTH: f32 = 4.712389;

/// One pellet's damage on a bare participant at a band.
fn on_fighter(weapon: WeaponType, band: Band) -> i32 {
    zoned_damage(weapon, weapon.damage_at(3.0), None, Some(band), false).0
}

/// A gun's per-shot head, torso and legs damage and its bare and armoured
/// clean-hit times for each.
type ZoneRow = (WeaponType, [i32; 3], [(f32, f32); 3]);

/// Clean-hit time to kill a pool, in seconds at the 20 Hz tick. The
/// Repeater pays its 0.30 s warmup before the first shot.
fn ttk(weapon: WeaponType, per_shot: i32, pool: i32) -> f32 {
    let shots = (pool + per_shot - 1) / per_shot;
    let warmup = if weapon == WeaponType::Repeater {
        crate::sim::repeater::WARMUP_TICKS as f32 / 20.0
    } else {
        0.0
    };
    (shots - 1) as f32 * weapon.cooldown_ticks() as f32 / 20.0 + warmup
}

#[test]
fn the_damage_and_time_to_kill_table_matches_the_plan_bare_and_armoured() {
    // (weapon, per-shot head, torso, legs, then bare and armoured TTK each).
    let table: [ZoneRow; 4] = [
        (
            WeaponType::Tack,
            [40, 20, 15],
            [(0.50, 1.00), (1.00, 2.25), (1.50, 3.25)],
        ),
        (
            WeaponType::Flechette,
            [37, 25, 18],
            [(0.40, 1.00), (0.60, 1.40), (1.00, 2.20)],
        ),
        (
            WeaponType::Repeater,
            [21, 14, 10],
            [(0.70, 1.20), (1.00, 1.70), (1.20, 2.20)],
        ),
        (
            WeaponType::Rail,
            [160, 80, 60],
            [(0.00, 1.00), (1.00, 2.00), (1.00, 3.00)],
        ),
    ];
    for (weapon, damage, times) in table {
        for ((band, expected), (bare, armoured)) in [Band::Head, Band::Torso, Band::Legs]
            .into_iter()
            .zip(damage)
            .zip(times)
        {
            let dealt = on_fighter(weapon, band);
            assert_eq!(dealt, expected, "{weapon:?} {band:?}");
            assert!(
                (ttk(weapon, dealt, 100) - bare).abs() < 1e-3,
                "{weapon:?} {band:?} bare {}",
                ttk(weapon, dealt, 100)
            );
            // Scrap armour is one pool after the multiplier: 100 + 100.
            assert!(
                (ttk(weapon, dealt, 200) - armoured).abs() < 1e-3,
                "{weapon:?} {band:?} armoured {}",
                ttk(weapon, dealt, 200)
            );
        }
    }
    // Scatter, per pellet in its full band, seven pellets a blast.
    let blast = |band| on_fighter(WeaponType::Scatter, band) * 7;
    assert_eq!(
        (blast(Band::Head), blast(Band::Torso), blast(Band::Legs)),
        (84, 70, 49)
    );
    assert!((ttk(WeaponType::Scatter, blast(Band::Head), 100) - 0.6).abs() < 1e-3);
    assert!((ttk(WeaponType::Scatter, blast(Band::Legs), 100) - 1.2).abs() < 1e-3);
    // The Sniper is precision too.
    assert_eq!(on_fighter(WeaponType::Sniper, Band::Head), 140);
    // The 1.0 bar: torso clean hits inside 0.5 to 1.2 s for the arcade guns,
    // and every non-power gun except the Rail needs at least 0.4 s by heads.
    for weapon in [
        WeaponType::Tack,
        WeaponType::Flechette,
        WeaponType::Repeater,
    ] {
        assert!(ttk(weapon, on_fighter(weapon, Band::Head), 100) >= 0.4 - 1e-3);
    }
    assert!(ttk(WeaponType::Scatter, blast(Band::Head), 100) >= 0.4 - 1e-3);
    for weapon in [WeaponType::Flechette, WeaponType::Rail] {
        let torso = ttk(weapon, on_fighter(weapon, Band::Torso), 100);
        assert!((0.5..=1.2).contains(&torso), "{weapon:?} {torso}");
    }
    assert!((0.5..=1.2).contains(&ttk(WeaponType::Scatter, blast(Band::Torso), 100)));
    // The Railgun's bare-head one-shot is the signature (Nick's open call).
    assert!(on_fighter(WeaponType::Rail, Band::Head) >= 100);
}

#[test]
fn weapons_without_zones_stay_flat_everywhere() {
    for weapon in [
        WeaponType::Arc,
        WeaponType::Rocket,
        WeaponType::Fists,
        WeaponType::Shiv,
        WeaponType::ArticleBlade,
    ] {
        for band in [Band::Head, Band::Torso, Band::Legs] {
            assert_eq!(
                zoned_damage(weapon, 30, None, Some(band), false),
                (30, None),
                "{weapon:?} {band:?}"
            );
        }
    }
    // A refused band (non-finite input) keeps the pellet flat and unzoned.
    assert_eq!(
        zoned_damage(WeaponType::Rail, 80, None, None, false),
        (80, None)
    );
}

fn duel() -> GameState {
    let mut state = GameState::new();
    state.seed(3);
    state.start_round();
    state.pickups.clear();
    state.add_player(Uuid::from_u128(1), "Shooter".into(), Role::Human);
    state.add_player(Uuid::from_u128(2), "Target".into(), Role::Agent);
    for (index, x) in [(0, 0.0), (1, 8.0)] {
        let p = &mut state.players[index];
        [p.x, p.y, p.z] = [x, PLAYER_FLOOR_Y, 0.0];
        p.vy = 0.0;
    }
    state.spawn_shields.clear();
    state
}

/// Fire one shot of `weapon` from player 0 at a height on player 1.
fn fire_at_height(state: &mut GameState, weapon: WeaponType, height: f32) -> ShotResult {
    let target = &state.players[1];
    let feet = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
    let shooter = &mut state.players[0];
    shooter.inventory.grant_weapon(weapon);
    shooter.weapon = weapon;
    shooter.fire_cooldown = 0;
    shooter.bloom = 0.0;
    state.set_action(
        Uuid::from_u128(1),
        Action {
            fire: true,
            look_at: Some(LookAt {
                x: Some(feet[0]),
                y: Some(feet[1] + height),
                z: Some(feet[2]),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    state.tick(0.05);
    state.set_action(Uuid::from_u128(1), Action::default());
    state
        .shot_results
        .iter()
        .find(|shot| shot.shooter_id == Uuid::from_u128(1))
        .cloned()
        .expect("the shooter fired")
}

#[test]
fn every_fighter_shares_one_table_and_armour_absorbs_after_the_multiplier() {
    for (height, zone, damage) in [
        (HEAD, HitZone::Head, 37),
        (TORSO, HitZone::Torso, 25),
        (LEGS, HitZone::Legs, 18),
    ] {
        // A human and an agent take the same number; armour soaks it after
        // the zone scaled it.
        for role in [Role::Agent, Role::Human] {
            let mut state = duel();
            state.players[1].role = role;
            state.players[1].armor = 100;
            let shot = fire_at_height(&mut state, WeaponType::Flechette, height);
            assert_eq!(shot.target_id, Some(Uuid::from_u128(2)));
            assert_eq!((shot.zone, shot.damage), (Some(zone), damage));
            assert_eq!(
                (state.players[1].hp, state.players[1].armor),
                (100, 100 - damage)
            );
        }
    }
    // A miss carries no zone, and the wire omits it.
    let mut state = duel();
    let shot = fire_at_height(&mut state, WeaponType::Rail, 4.0);
    assert!(!shot.hit && shot.zone.is_none());
    assert!(serde_json::to_value(&shot).unwrap().get("zone").is_none());
    // Spawn shield: the body stops the shot and takes nothing, so no zone.
    let mut state = duel();
    state.spawn_shields.insert(Uuid::from_u128(2), 20);
    let shot = fire_at_height(&mut state, WeaponType::Rail, HEAD);
    assert!(shot.hit && shot.damage == 0 && shot.zone.is_none());
}

#[test]
fn bands_drop_with_a_crouch_on_the_live_body() {
    let mut state = duel();
    // The target holds its crouch through every tick.
    state.set_action(
        Uuid::from_u128(2),
        Action {
            duck: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(state.players[1].ducking);
    let drop = crate::movement::BODY_HEIGHT - crate::movement::DUCK_HEIGHT;
    for (height, zone) in [
        (HEAD - drop, HitZone::Head),
        (TORSO - drop, HitZone::Torso),
        (LEGS - drop + 0.1, HitZone::Legs),
    ] {
        let shot = fire_at_height(&mut state, WeaponType::Tack, height);
        assert_eq!(shot.zone, Some(zone), "{height}");
        state.tick(0.05);
    }
}

#[test]
fn zone_wire_names_are_snake_case_and_strict() {
    for (zone, name) in [
        (HitZone::Head, "head"),
        (HitZone::Torso, "torso"),
        (HitZone::Legs, "legs"),
        (HitZone::Plate, "plate"),
        (HitZone::Weak, "weak"),
    ] {
        assert_eq!(serde_json::to_value(zone).unwrap(), json!(name));
        assert_eq!(
            serde_json::from_value::<HitZone>(json!(name)).unwrap(),
            zone
        );
    }
    assert!(serde_json::from_value::<HitZone>(json!("arm")).is_err());
    // The most telling zone wins a folded blast.
    assert_eq!(
        HitZone::most_telling(Some(HitZone::Legs), HitZone::Plate),
        HitZone::Plate
    );
    assert_eq!(
        HitZone::most_telling(Some(HitZone::Weak), HitZone::Head),
        HitZone::Weak
    );
    assert_eq!(HitZone::most_telling(None, HitZone::Legs), HitZone::Legs);
}

/// One campaign body `distance` metres north of the shooter, facing it.
fn lane(kind: &str, control: &str, distance: f32) -> (GameSession, Uuid, Uuid) {
    let doc = json!({
        "version":1,"map_id":1000,"name":"Zone lane","half_extent":64,
        "ground":"concrete","equipment":"discovery","solids":[],
        "spawns":[{"id":"entry","feet":[0,0,-20],"yaw":1.5707964}],
        "landmarks":[{"id":"far","feet":[0,0,50]}],
        "encounters":[{
            "id":"lane","regions":[{"min":[-64,0,-64],"max":[64,2,64]}],
            "enemies":[{"id":"target","kind":kind,"feet":[0,0,-20.0 + distance],
                "yaw":FACING_SOUTH,"control":control}]
        }]
    });
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let id = Uuid::from_u128(900);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    session.tick_messages(0.05);
    let target = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    place(&mut session, id, [0.0, 0.0, -20.0]);
    (session, id, target)
}

fn place(session: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
}

fn body(session: &GameSession, id: Uuid) -> &crate::sim::Player {
    session.state.players.iter().find(|p| p.id == id).unwrap()
}

/// Fire at a height on the target, from where the shooter stands.
fn shoot(
    session: &mut GameSession,
    id: Uuid,
    target: Uuid,
    weapon: WeaponType,
    height: f32,
) -> ShotResult {
    let t = body(session, target);
    let point = [t.x, t.y - PLAYER_FLOOR_Y + height, t.z];
    let p = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    p.inventory.grant_weapon(weapon);
    p.weapon = weapon;
    p.fire_cooldown = 0;
    p.bloom = 0.0;
    session.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    session.state.set_action(id, Action::default());
    session
        .state
        .shot_results
        .iter()
        .find(|shot| shot.shooter_id == id)
        .cloned()
        .expect("the visitor fired")
}

fn phase(session: &GameSession, id: Uuid) -> EnemyPhase {
    match body(session, id).campaign {
        Some(CampaignActor::Hostile { phase, .. }) => phase,
        other => panic!("not hostile: {other:?}"),
    }
}

fn mast_broken(session: &GameSession, id: Uuid) -> bool {
    matches!(
        body(session, id).campaign,
        Some(CampaignActor::Hostile {
            mast_broken: true,
            ..
        })
    )
}

#[test]
fn a_union_bot_turns_its_plate_and_doubles_on_its_optic_for_every_gun() {
    for weapon in [WeaponType::Tack, WeaponType::Flechette, WeaponType::Rail] {
        let (mut session, id, sweeper) = lane("sweeper", "union", 8.0);
        let base = weapon.damage();
        let plate = shoot(&mut session, id, sweeper, weapon, TORSO);
        assert_eq!(
            (plate.zone, plate.damage),
            (Some(HitZone::Plate), base / 2),
            "{weapon:?}"
        );
        let (mut session, id, sweeper) = lane("sweeper", "union", 8.0);
        let optic = shoot(&mut session, id, sweeper, weapon, HEAD);
        // The optic is 2x for an automatic too: the red light is the target.
        assert_eq!(
            (optic.zone, optic.damage),
            (Some(HitZone::Weak), base * 2),
            "{weapon:?}"
        );
        let (mut session, id, sweeper) = lane("sweeper", "union", 8.0);
        let legs = shoot(&mut session, id, sweeper, weapon, LEGS);
        assert_eq!(
            (legs.zone, legs.damage),
            (Some(HitZone::Legs), base * 3 / 4),
            "{weapon:?}"
        );
    }
    // The lock an agent sends takes the optic when it can see it.
    let (mut session, id, sweeper) = lane("sweeper", "union", 8.0);
    let p = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    p.inventory.grant_weapon(WeaponType::Tack);
    p.weapon = WeaponType::Tack;
    p.fire_cooldown = 0;
    session.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(sweeper),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    let shot = session
        .state
        .shot_results
        .iter()
        .find(|shot| shot.shooter_id == id)
        .cloned()
        .unwrap();
    assert_eq!((shot.zone, shot.damage), (Some(HitZone::Weak), 40));
}

#[test]
fn an_absorbed_bot_keeps_its_chassis_and_its_weak_spot_is_the_cyan_light() {
    let (mut session, id, bot) = lane("sweeper", "absorbed", 8.0);
    assert!(matches!(
        body(&session, bot).campaign,
        Some(CampaignActor::Hostile {
            control: crate::protocol::ControlDomain::Absorbed,
            ..
        })
    ));
    let light = shoot(&mut session, id, bot, WeaponType::Flechette, HEAD);
    assert_eq!((light.zone, light.damage), (Some(HitZone::Weak), 50));
    let (mut session, id, bot) = lane("sweeper", "absorbed", 8.0);
    let plate = shoot(&mut session, id, bot, WeaponType::Flechette, TORSO);
    assert_eq!((plate.zone, plate.damage), (Some(HitZone::Plate), 12));
}

#[test]
fn a_heavy_sweepers_vent_only_opens_from_behind() {
    let (mut session, id, heavy) = lane("heavy_sweeper", "union", 8.0);
    let front = shoot(&mut session, id, heavy, WeaponType::Rail, TORSO);
    assert_eq!((front.zone, front.damage), (Some(HitZone::Plate), 40));
    // Behind it: the vent takes half again.
    let (mut session, id, heavy) = lane("heavy_sweeper", "union", 8.0);
    place(&mut session, id, [0.0, 0.0, -4.0]);
    let rear = shoot(&mut session, id, heavy, WeaponType::Rail, TORSO);
    assert_eq!((rear.zone, rear.damage), (Some(HitZone::Weak), 120));
    // A plain Sweeper has no vent: its back is plate too.
    let (mut session, id, sweeper) = lane("sweeper", "union", 8.0);
    place(&mut session, id, [0.0, 0.0, -4.0]);
    let back = shoot(&mut session, id, sweeper, WeaponType::Rail, TORSO);
    assert_eq!((back.zone, back.damage), (Some(HitZone::Plate), 40));
}

#[test]
fn breaking_the_mast_cancels_the_precision_shot_and_the_long_sight() {
    // A marksman 60 m off, inside its own 90 m sight and outside a guard's 32 m.
    let (mut session, id, marksman) = lane("ranged_sweeper", "union", 60.0);
    for _ in 0..60 {
        session.tick_messages(0.05);
        if phase(&session, marksman) == EnemyPhase::Windup {
            break;
        }
    }
    assert_eq!(
        phase(&session, marksman),
        EnemyPhase::Windup,
        "it glints at 60 m"
    );
    // Failure path first: a plate hit staggers it but leaves the mast.
    let plate = shoot(&mut session, id, marksman, WeaponType::Sniper, TORSO);
    assert_eq!(plate.zone, Some(HitZone::Plate));
    assert!(!mast_broken(&session, marksman));
    for _ in 0..80 {
        session.tick_messages(0.05);
        if phase(&session, marksman) == EnemyPhase::Windup {
            break;
        }
    }
    assert_eq!(
        phase(&session, marksman),
        EnemyPhase::Windup,
        "an intact mast glints again"
    );
    // Keep the body standing through the mast hit so the sight change shows.
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == marksman)
        .unwrap()
        .hp = 500;
    // The mast: a thin column above the crown.
    let mast = shoot(
        &mut session,
        id,
        marksman,
        WeaponType::Sniper,
        crate::combat::FIGHTER_HEIGHT + 0.05 + crate::combat::MAST_HEIGHT * 0.5,
    );
    assert_eq!(mast.zone, Some(HitZone::Weak));
    assert_eq!(mast.damage, WeaponType::Sniper.damage());
    assert!(mast_broken(&session, marksman));
    assert_ne!(
        phase(&session, marksman),
        EnemyPhase::Windup,
        "the shot is cancelled"
    );
    // The wire says so, and the mast is gone from the volume.
    let snapshot = serde_json::to_value(session.state.snapshot()).unwrap();
    let wire = snapshot["players"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == json!(marksman))
        .unwrap();
    assert_eq!(wire["campaign"]["mast_broken"], json!(true));
    // Without the mast it never glints at 60 m again.
    let hp = body(&session, marksman).hp;
    for _ in 0..200 {
        session.tick_messages(0.05);
        assert_ne!(phase(&session, marksman), EnemyPhase::Windup);
        assert_ne!(phase(&session, marksman), EnemyPhase::Firing);
    }
    assert_eq!(body(&session, id).hp, 100);
    let over = shoot(
        &mut session,
        id,
        marksman,
        WeaponType::Sniper,
        crate::combat::FIGHTER_HEIGHT + 0.05 + crate::combat::MAST_HEIGHT * 0.5,
    );
    assert!(!over.hit, "no mast left to strike: {over:?}");
    assert_eq!(body(&session, marksman).hp, hp);
    // Close in to 20 m: it still sees and shoots an open body.
    place(&mut session, id, [0.0, 0.0, 20.0]);
    let mut glinted = false;
    for _ in 0..120 {
        session.tick_messages(0.05);
        if phase(&session, marksman) == EnemyPhase::Windup {
            glinted = true;
            break;
        }
    }
    assert!(glinted, "inside 32 m a mastless marksman still fights");
}

#[test]
fn an_enforcers_breastplate_halves_and_its_face_takes_half_again() {
    let (mut session, id, enforcer) = lane("enforcer", "union", 8.0);
    let plate = shoot(&mut session, id, enforcer, WeaponType::Rail, TORSO);
    assert_eq!((plate.zone, plate.damage), (Some(HitZone::Plate), 40));
    let (mut session, id, enforcer) = lane("enforcer", "union", 8.0);
    let face = shoot(&mut session, id, enforcer, WeaponType::Flechette, HEAD);
    // 3/2 for every gun, an automatic included.
    assert_eq!((face.zone, face.damage), (Some(HitZone::Head), 37));
    let (mut session, id, enforcer) = lane("enforcer", "union", 8.0);
    let legs = shoot(&mut session, id, enforcer, WeaponType::Rail, LEGS);
    assert_eq!((legs.zone, legs.damage), (Some(HitZone::Legs), 80));
}

#[test]
fn a_union_person_uses_the_fighter_table() {
    let (mut session, id, clerk) = lane("clerk", "union", 8.0);
    let head = shoot(&mut session, id, clerk, WeaponType::Flechette, HEAD);
    assert_eq!((head.zone, head.damage), (Some(HitZone::Head), 37));
}

#[test]
fn band_edges_hold_for_the_standing_crouched_short_and_flying_bodies() {
    let hostile = |kind| {
        Some(CampaignActor::Hostile {
            kind,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
            mast_broken: false,
            control: Default::default(),
        })
    };
    let e = 0.001;
    // Standing.
    assert_eq!(band_for(0.0, HEAD_GATE, None, false), Some(Band::Head));
    assert_eq!(band_for(0.0, HEAD_GATE - e, None, false), Some(Band::Torso));
    assert_eq!(band_for(0.0, LEG_GATE, None, false), Some(Band::Torso));
    assert_eq!(band_for(0.0, LEG_GATE - e, None, false), Some(Band::Legs));
    assert_eq!(band_for(0.0, 0.0, None, false), Some(Band::Legs));
    // Crouched: every gate drops 0.45 m.
    let drop = crate::movement::BODY_HEIGHT - crate::movement::DUCK_HEIGHT;
    assert_eq!(
        band_for(0.0, HEAD_GATE - drop, None, true),
        Some(Band::Head)
    );
    assert_eq!(
        band_for(0.0, HEAD_GATE - drop - e, None, true),
        Some(Band::Torso)
    );
    assert_eq!(
        band_for(0.0, LEG_GATE - drop, None, true),
        Some(Band::Torso)
    );
    assert_eq!(
        band_for(0.0, LEG_GATE - drop - e, None, true),
        Some(Band::Legs)
    );
    // Feet above the floor: bands ride with the body.
    assert_eq!(
        band_for(2.0, 2.0 + HEAD_GATE, None, false),
        Some(Band::Head)
    );
    // Short and flying bodies: the top quarter is the head, no legs.
    for (kind, height) in [
        (EnemyKind::Crawler, crate::combat::CRAWLER_HEIGHT),
        (EnemyKind::Notary, crate::combat::NOTARY_HEIGHT),
        (EnemyKind::Assessor, crate::combat::ASSESSOR_HEIGHT),
    ] {
        let id = hostile(kind);
        assert_eq!(
            band_for(0.0, height * 0.75, id, false),
            Some(Band::Head),
            "{kind:?}"
        );
        assert_eq!(
            band_for(0.0, height * 0.75 - e, id, false),
            Some(Band::Torso),
            "{kind:?}"
        );
        assert_eq!(
            band_for(0.0, 0.01, id, false),
            Some(Band::Torso),
            "{kind:?}"
        );
        // A crouch flag never changes a short body.
        assert_eq!(
            band_for(0.0, height * 0.75, id, true),
            Some(Band::Head),
            "{kind:?}"
        );
    }
    // Only an intact marksman has a mast above the crown.
    let crown = crate::combat::FIGHTER_HEIGHT + 0.1;
    assert_eq!(
        band_for(0.0, crown, hostile(EnemyKind::RangedSweeper), false),
        Some(Band::Mast)
    );
    assert_eq!(
        band_for(0.0, crown, hostile(EnemyKind::Sweeper), false),
        Some(Band::Head)
    );
    // Non-finite input is refused.
    assert_eq!(band_for(f32::NAN, 1.0, None, false), None);
    assert_eq!(band_for(0.0, f32::INFINITY, None, false), None);
}

#[test]
fn a_paver_takes_full_damage_only_on_its_cyan_lens_and_lit_grille() {
    let (mut session, id, paver) = lane("paver", "restoration", 8.0);
    let lens = shoot(&mut session, id, paver, WeaponType::Rail, HEAD);
    assert_eq!((lens.zone, lens.damage), (Some(HitZone::Weak), 80));
    let (mut session, id, paver) = lane("paver", "restoration", 8.0);
    let shell = shoot(&mut session, id, paver, WeaponType::Rail, TORSO);
    assert_eq!((shell.zone, shell.damage), (Some(HitZone::Plate), 40));
    // From behind, the head band is housing; the grille is dark at rest.
    let (mut session, id, paver) = lane("paver", "restoration", 8.0);
    place(&mut session, id, [0.0, 0.0, -4.0]);
    let back_head = shoot(&mut session, id, paver, WeaponType::Rail, HEAD);
    assert_eq!(back_head.zone, Some(HitZone::Plate));
    let working = Some(CampaignActor::Hostile {
        kind: EnemyKind::Paver,
        phase: EnemyPhase::Recovery,
        phase_started: 0,
        phase_ends: 0,
        seated: false,
        mast_broken: false,
        control: crate::protocol::ControlDomain::Restoration,
    });
    assert_eq!(
        zoned_damage(WeaponType::Rail, 80, working, Some(Band::Torso), true),
        (80, Some(HitZone::Weak))
    );
    assert_eq!(
        zoned_damage(WeaponType::Rail, 80, working, Some(Band::Torso), false),
        (40, Some(HitZone::Plate))
    );
}

#[test]
fn a_broken_mast_is_strict_on_the_actor_wire() {
    let read = |text: &str| serde_json::from_str::<CampaignActor>(text);
    let broken = read(
        r#"{"side":"union","kind":"ranged_sweeper","phase":"idle","phase_started":0,"phase_ends":0,"mast_broken":true}"#,
    )
    .unwrap();
    assert!(matches!(
        broken,
        CampaignActor::Hostile {
            mast_broken: true,
            ..
        }
    ));
    assert_eq!(
        serde_json::to_value(broken).unwrap()["mast_broken"],
        json!(true)
    );
    // An absorbed marksman can lose its mast too.
    assert!(read(
        r#"{"side":"inheritance","control":"absorbed","kind":"ranged_sweeper","phase":"idle","phase_started":0,"phase_ends":0,"mast_broken":true}"#,
    )
    .is_ok());
    // Only a marksman has a mast; an intact one omits the field.
    assert!(read(
        r#"{"side":"union","kind":"sweeper","phase":"idle","phase_started":0,"phase_ends":0,"mast_broken":true}"#,
    )
    .is_err());
    let intact = read(
        r#"{"side":"union","kind":"ranged_sweeper","phase":"idle","phase_started":0,"phase_ends":0}"#,
    )
    .unwrap();
    assert!(serde_json::to_value(intact)
        .unwrap()
        .get("mast_broken")
        .is_none());
}
