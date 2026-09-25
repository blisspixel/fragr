//! Heavy Sweeper and Turret: seeded tick tests of their tells, armor, sight
//! rules, gait and retry through the shared campaign actor wire.
use crate::encounters::enemy::{attack_timing, STAGGER_DAMAGE};
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, LookAt, Role, WeaponType,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::json;
use uuid::Uuid;

const FACING_ENTRY: f32 = 4.712389;

fn fixture(kind: &str, cover: bool) -> (GameSession, Uuid, Uuid) {
    let mut doc = json!({
        "version":1,"map_id":1000,"name":"Heavy and turret fixture","half_extent":12,
        "ground":"concrete","equipment":"discovery","solids":[],
        "spawns":[{"id":"entry","feet":[0,0,-6],"yaw":1.5707964}],
        "landmarks":[{"id":"exit","feet":[0,0,10]}],
        "encounters":[{
            "id":"range","regions":[{"min":[-12,0,-12],"max":[12,2,12]}],
            "enemies":[{"id":"guard","kind":kind,"feet":[0,0,4],"yaw":FACING_ENTRY}]
        }]
    });
    if cover {
        doc["solids"] = json!([{"id":"cover","min":[3,0,-7],"max":[6,3,-5],"surface":"enamel"}]);
    }
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let id = Uuid::from_u128(100);
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

fn identity(session: &GameSession, id: Uuid) -> (EnemyKind, EnemyPhase, u64, u64) {
    match session
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .campaign
        .unwrap()
    {
        CampaignActor::Union {
            kind,
            phase,
            phase_started,
            phase_ends,
        } => (kind, phase, phase_started, phase_ends),
        CampaignActor::Participant {} => panic!("expected enemy"),
    }
}

fn phase(session: &GameSession, id: Uuid) -> EnemyPhase {
    identity(session, id).1
}

fn body(session: &GameSession, id: Uuid) -> &crate::sim::Player {
    session.state.players.iter().find(|p| p.id == id).unwrap()
}

fn place(session: &mut GameSession, id: Uuid, x: f32, z: f32) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.x = x;
    player.z = z;
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

fn enemy_shots(session: &GameSession, guard: Uuid) -> usize {
    session
        .state
        .shot_results
        .iter()
        .filter(|shot| shot.shooter_id == guard)
        .count()
}

fn shoot(session: &mut GameSession, shooter: Uuid, target: Uuid, weapon: WeaponType) {
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

#[test]
fn turret_tracks_in_place_and_broken_sight_cancels_the_charged_shot() {
    let (mut session, id, turret) = fixture("turret", true);
    assert_eq!(body(&session, turret).hp, 100);
    assert_eq!(body(&session, turret).weapon, WeaponType::Rail);
    until(&mut session, turret, EnemyPhase::Windup, 40);
    let (kind, _, start, end) = identity(&session, turret);
    assert_eq!(kind, EnemyKind::Turret);
    assert_eq!(
        end - start,
        attack_timing(EnemyKind::Turret, CampaignDifficulty::Standard).0
    );
    // Step behind cover mid-tell. The turret loses track instead of firing.
    place(&mut session, id, 4.5, -8.5);
    advance(&mut session, 1);
    assert_eq!(phase(&session, turret), EnemyPhase::Recovery);
    while session.state.tick <= end + 2 {
        advance(&mut session, 1);
        assert_eq!(enemy_shots(&session, turret), 0);
    }
    assert_eq!(session.state.players[0].hp, 100);
    until(&mut session, turret, EnemyPhase::Idle, 20);
    // Idle is a visible sweep of the head, never a step of the feet.
    let mut last = body(&session, turret).yaw;
    let mut swept = 0.0;
    for _ in 0..10 {
        advance(&mut session, 1);
        swept += (body(&session, turret).yaw - last).abs();
        last = body(&session, turret).yaw;
    }
    let turret_body = body(&session, turret);
    assert!(swept > 0.3, "idle sweep turns the head, swept {swept}");
    assert_eq!((turret_body.x, turret_body.z), (0.0, 4.0));
    assert_eq!(phase(&session, turret), EnemyPhase::Idle);
}

#[test]
fn turret_ignores_a_flank_behind_its_sweep_and_can_be_destroyed_there() {
    let (mut session, id, turret) = fixture("turret", false);
    place(&mut session, id, 0.0, 9.0);
    for _ in 0..60 {
        advance(&mut session, 1);
        assert_eq!(phase(&session, turret), EnemyPhase::Idle);
        assert_eq!(enemy_shots(&session, turret), 0);
    }
    // A pistol hit is below the stagger threshold: armor does not flinch.
    shoot(&mut session, id, turret, WeaponType::Tack);
    advance(&mut session, 1);
    assert_eq!(body(&session, turret).hp, 80);
    assert_ne!(phase(&session, turret), EnemyPhase::Hit);
    shoot(&mut session, id, turret, WeaponType::Rail);
    assert_eq!(phase(&session, turret), EnemyPhase::Dead);
    let snapshot = serde_json::to_value(session.state.snapshot()).unwrap();
    let wire = snapshot["players"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == json!(turret))
        .unwrap();
    assert_eq!(wire["campaign"]["kind"], "turret");
    assert_eq!(wire["campaign"]["phase"], "dead");
}

#[test]
fn heavy_sweeper_shrugs_light_hits_and_staggers_once_on_a_heavy_one() {
    let (mut session, id, heavy) = fixture("heavy_sweeper", false);
    assert_eq!(body(&session, heavy).hp, 160);
    until(&mut session, heavy, EnemyPhase::Windup, 5);
    let (_, _, _, end) = identity(&session, heavy);
    shoot(&mut session, id, heavy, WeaponType::Tack);
    advance(&mut session, 1);
    assert_eq!(phase(&session, heavy), EnemyPhase::Windup, "light hit");
    assert!(WeaponType::Rail.damage() >= STAGGER_DAMAGE);
    shoot(&mut session, id, heavy, WeaponType::Rail);
    advance(&mut session, 1);
    let (_, current, start, stagger_end) = identity(&session, heavy);
    assert_eq!(current, EnemyPhase::Hit);
    assert_eq!(stagger_end - start, 16);
    assert!(start < end, "the stagger interrupted the tell");
    // A second heavy hit inside the stagger does not extend it.
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == heavy)
        .unwrap()
        .hp = 200;
    advance(&mut session, 1);
    shoot(&mut session, id, heavy, WeaponType::Rail);
    advance(&mut session, 1);
    assert_eq!(identity(&session, heavy).3, stagger_end);
    while session.state.tick < stagger_end {
        advance(&mut session, 1);
        assert_eq!(enemy_shots(&session, heavy), 0);
    }
    assert_eq!(session.state.players[0].hp, 100);
    until(&mut session, heavy, EnemyPhase::Windup, 3);
}

#[test]
fn heavy_sweeper_bursts_four_then_shuffles_sideways_at_a_heavy_gait() {
    let (mut session, id, heavy) = fixture("heavy_sweeper", false);
    session.state.players[0].hp = 1000;
    until(&mut session, heavy, EnemyPhase::Firing, 40);
    let mut shots = enemy_shots(&session, heavy);
    for _ in 0..20 {
        advance(&mut session, 1);
        shots += enemy_shots(&session, heavy);
        if phase(&session, heavy) == EnemyPhase::Recovery {
            break;
        }
    }
    assert_eq!(shots, 4);
    assert_eq!(session.state.players[0].hp, 900);
    until(&mut session, heavy, EnemyPhase::Moving, 40);
    let start = (body(&session, heavy).x, body(&session, heavy).z);
    let mut last = start;
    for _ in 0..10 {
        advance(&mut session, 1);
        let now = (body(&session, heavy).x, body(&session, heavy).z);
        let step = (now.0 - last.0).hypot(now.1 - last.1);
        assert!(step <= 5.0 * 0.3 * 0.05 + 1e-3, "heavy gait, got {step}");
        last = now;
    }
    assert!(
        (last.0 - start.0).abs() > 0.3,
        "moves sideways, not forward"
    );
    assert!((last.1 - start.1).abs() < 0.1);
    until(&mut session, heavy, EnemyPhase::Windup, 30);
    let _ = id;
}

#[test]
fn party_wipe_resets_destroyed_turret_and_heavy_for_retry() {
    let doc = include_bytes!("../../maps/test/heavy-turret-range.json");
    let map = AuthoredMap::read(doc.as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(7);
    let id = Uuid::from_u128(100);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    advance(&mut session, 1);
    let guards: Vec<(Uuid, i32, f32)> = session
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| (p.id, p.hp, p.yaw))
        .collect();
    assert_eq!(guards.len(), 2);
    assert_eq!(
        guards.iter().map(|g| g.1).collect::<Vec<_>>(),
        vec![100, 160]
    );
    for &(guard, _, _) in &guards {
        shoot(&mut session, id, guard, WeaponType::Rail);
        shoot(&mut session, id, guard, WeaponType::Rail);
        assert_eq!(phase(&session, guard), EnemyPhase::Dead);
    }
    session.state.players[0].hp = 0;
    session.state.players[0].respawn_timer = Some(5);
    advance(&mut session, 6);
    let restored: Vec<(Uuid, i32, f32)> = session
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| (p.id, p.hp, p.yaw))
        .collect();
    assert_eq!(restored.len(), 2);
    for (before, after) in guards.iter().zip(&restored) {
        assert_ne!(before.0, after.0, "retry places fresh bodies");
        assert_eq!((before.1, before.2), (after.1, after.2));
        assert_eq!(phase(&session, after.0), EnemyPhase::Idle);
    }
    assert_eq!(body(&session, id).y, PLAYER_FLOOR_Y);
}

#[test]
fn new_kinds_are_strict_on_the_actor_wire() {
    for (kind, wire) in [
        (EnemyKind::HeavySweeper, "heavy_sweeper"),
        (EnemyKind::Turret, "turret"),
    ] {
        let actor = CampaignActor::Union {
            kind,
            phase: EnemyPhase::Windup,
            phase_started: 10,
            phase_ends: 36,
        };
        let json = serde_json::to_value(actor).unwrap();
        assert_eq!(json["kind"], wire);
        assert_eq!(
            serde_json::from_value::<CampaignActor>(json).unwrap(),
            actor
        );
    }
    assert!(serde_json::from_value::<CampaignActor>(json!({
        "side":"union","kind":"heavy","phase":"idle","phase_started":0,"phase_ends":0
    }))
    .is_err());
}
