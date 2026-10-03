//! Seeded Auditor repair channels, their snap paths, the hard limit and the plate.
use crate::encounters::enemy::{attack_timing, channel_ticks, REPAIR_RECOVERY_TICKS};
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, LookAt, Role, WeaponType,
    AUDITOR_REPAIRS,
};
use crate::session::GameSession;
use serde_json::json;
use uuid::Uuid;

/// A screen wall hides the participant at z = -6 from the custody bay.
fn fixture() -> (GameSession, Uuid) {
    let doc = json!({
        "version":1,"map_id":1098,"name":"Auditor fixture","half_extent":24,
        "ground":"concrete","equipment":"discovery",
        "solids":[
            {"id":"screen","min":[-24,0,-3],"max":[16,3,-2.5],"surface":"concrete"},
            {"id":"bay_pillar","min":[-12,0,6],"max":[-10,3,8],"surface":"concrete"}
        ],
        "spawns":[{"id":"entry","feet":[0,0,-6],"yaw":1.5707964}],
        "landmarks":[{"id":"bay","feet":[0,0,14]}],
        "encounters":[{"id":"audit","regions":[{"min":[-24,0,-24],"max":[24,2,24]}],
            "enemies":[
                {"id":"auditor","kind":"auditor","feet":[0,0,8],"yaw":4.712389},
                {"id":"sweeper_a","kind":"sweeper","feet":[-3,0,10],"yaw":4.712389},
                {"id":"sweeper_b","kind":"sweeper","feet":[3,0,10],"yaw":4.712389},
                {"id":"clerk","kind":"clerk","feet":[6,0,12],"yaw":4.712389}
            ]}]
    });
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    let participant = Uuid::from_u128(0x0808);
    session
        .state
        .add_player(participant, "Visitor".into(), Role::Human);
    advance(&mut session, 2);
    (session, participant)
}

fn advance(session: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        session.tick_messages(0.05);
    }
}

fn enemy(session: &GameSession, name: &str) -> Uuid {
    session
        .state
        .players
        .iter()
        .find(|p| p.name == name && p.is_campaign_enemy())
        .unwrap()
        .id
}

fn body(session: &GameSession, id: Uuid) -> Option<&crate::sim::Player> {
    session.state.players.iter().find(|p| p.id == id)
}

fn phase(session: &GameSession, id: Uuid) -> EnemyPhase {
    match body(session, id).unwrap().campaign.unwrap() {
        CampaignActor::Union { phase, .. } => phase,
        _ => panic!("expected Union actor"),
    }
}

fn window(session: &GameSession, id: Uuid) -> (u64, u64) {
    match body(session, id).unwrap().campaign.unwrap() {
        CampaignActor::Union {
            phase_started,
            phase_ends,
            ..
        } => (phase_started, phase_ends),
        _ => panic!("expected Union actor"),
    }
}

fn set(session: &mut GameSession, id: Uuid, x: f32, z: f32) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.x = x;
    player.z = z;
}

fn heal(session: &mut GameSession, id: Uuid) {
    if let Some(player) = session.state.players.iter_mut().find(|p| p.id == id) {
        player.hp = 100;
        player.armor = 100;
    }
}

/// One aimed shot from a chosen stance, then back behind the screen.
fn shoot(session: &mut GameSession, participant: Uuid, target: Uuid, weapon: WeaponType) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == participant)
        .unwrap();
    player.inventory.grant_weapon(weapon);
    player.weapon = weapon;
    player.fire_cooldown = 0;
    session.state.set_action(
        participant,
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
    session.state.set_action(participant, Action::default());
}

/// Drop a bot to a sliver and finish it from close range in front of it.
fn disable(session: &mut GameSession, participant: Uuid, target: Uuid) {
    let (x, z) = {
        let body = body(session, target).unwrap();
        (body.x, body.z)
    };
    if let Some(player) = session.state.players.iter_mut().find(|p| p.id == target) {
        player.hp = 1;
        player.armor = 0;
    }
    set(session, participant, x, z - 2.5);
    shoot(session, participant, target, WeaponType::Rail);
    assert!(body(session, target).unwrap().hp <= 0, "the bot dropped");
    assert_eq!(phase(session, target), EnemyPhase::Dead);
    set(session, participant, 0.0, -6.0);
    heal(session, participant);
}

fn auditor_state(session: &GameSession) -> crate::protocol::AuditorState {
    session.state.snapshot().auditors[0]
}

/// Advance until the Auditor opens a channel, returning ticks spent.
fn until_channel(session: &mut GameSession, auditor: Uuid, participant: Uuid) -> usize {
    for spent in 1..=40 {
        advance(session, 1);
        heal(session, participant);
        if phase(session, auditor) == EnemyPhase::Channeling {
            return spent;
        }
    }
    panic!("the Auditor never opened a channel");
}

#[test]
fn auditor_body_and_timing_rows_are_part_of_rules_revision_three() {
    assert_eq!(crate::encounters::enemy::body(EnemyKind::Auditor).0, 120);
    assert_eq!(
        crate::encounters::enemy::body(EnemyKind::Auditor).1,
        WeaponType::Tack
    );
    assert_eq!(
        crate::encounters::gait(Some(CampaignActor::Union {
            kind: EnemyKind::Auditor,
            phase: EnemyPhase::Moving,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
        })),
        0.4
    );
    assert_eq!(
        [
            attack_timing(EnemyKind::Auditor, CampaignDifficulty::Assisted),
            attack_timing(EnemyKind::Auditor, CampaignDifficulty::Standard),
            attack_timing(EnemyKind::Auditor, CampaignDifficulty::Severe),
        ],
        [(22, 32), (14, 22), (12, 18)]
    );
    assert_eq!(
        [
            channel_ticks(CampaignDifficulty::Assisted),
            channel_ticks(CampaignDifficulty::Standard),
            channel_ticks(CampaignDifficulty::Severe),
        ],
        [60, 44, 36]
    );
    assert_eq!(AUDITOR_REPAIRS, 2);
    assert!(crate::encounters::enemy::repairable(EnemyKind::Sweeper));
    assert!(crate::encounters::enemy::repairable(
        EnemyKind::HeavySweeper
    ));
    for person in [EnemyKind::Clerk, EnemyKind::Auditor] {
        assert!(!crate::encounters::enemy::repairable(person));
    }
}

#[test]
fn a_disabled_sweeper_is_repaired_twice_and_never_a_third_time() {
    let (mut session, participant) = fixture();
    let auditor = enemy(&session, "auditor");
    let sweeper = enemy(&session, "sweeper_a");
    assert_eq!(body(&session, auditor).unwrap().hp, 120);
    assert_eq!(auditor_state(&session).repairs_left, 2);
    assert_eq!(auditor_state(&session).channel_target, None);
    for repair in 0..2 {
        disable(&mut session, participant, sweeper);
        until_channel(&mut session, auditor, participant);
        let state = auditor_state(&session);
        assert_eq!(state.channel_target, Some(sweeper));
        let (started, ends) = window(&session, auditor);
        assert_eq!(ends - started, channel_ticks(CampaignDifficulty::Standard));
        // The disabled body is held for the whole channel.
        let mut held = 0;
        while phase(&session, auditor) == EnemyPhase::Channeling {
            assert_eq!(phase(&session, sweeper), EnemyPhase::Dead);
            assert!(window(&session, sweeper).1 > window(&session, auditor).1);
            let (down, held_until) = window(&session, sweeper);
            assert!(held_until - down <= crate::encounters::enemy::DISABLED_HOLD_LIMIT);
            advance(&mut session, 1);
            heal(&mut session, participant);
            held += 1;
        }
        assert_eq!(held as u64, channel_ticks(CampaignDifficulty::Standard));
        assert_eq!(body(&session, sweeper).unwrap().hp, 40, "half of 80");
        assert_eq!(phase(&session, sweeper), EnemyPhase::Recovery);
        let (up, ready) = window(&session, sweeper);
        assert_eq!(ready - up, REPAIR_RECOVERY_TICKS);
        assert_eq!(auditor_state(&session).repairs_left, 1 - repair);
        assert_eq!(auditor_state(&session).channel_target, None);
    }
    // A third disable is final: the body leaves after its own window.
    disable(&mut session, participant, sweeper);
    for _ in 0..60 {
        advance(&mut session, 1);
        heal(&mut session, participant);
        assert_ne!(phase(&session, auditor), EnemyPhase::Channeling);
        if body(&session, sweeper).is_none() {
            break;
        }
    }
    assert!(body(&session, sweeper).is_none());
    assert_eq!(auditor_state(&session).repairs_left, 0);
}

#[test]
fn a_hit_broken_sight_a_missing_body_or_an_occupied_spot_snaps_the_channel() {
    // A damaging hit snaps it and spends nothing.
    let (mut session, participant) = fixture();
    let auditor = enemy(&session, "auditor");
    let sweeper = enemy(&session, "sweeper_a");
    disable(&mut session, participant, sweeper);
    until_channel(&mut session, auditor, participant);
    set(&mut session, participant, 4.0, 2.0);
    shoot(&mut session, participant, auditor, WeaponType::Tack);
    assert!(body(&session, auditor).unwrap().hp < 120);
    assert_eq!(phase(&session, auditor), EnemyPhase::Hit);
    assert_eq!(auditor_state(&session).channel_target, None);
    assert_eq!(auditor_state(&session).repairs_left, 2);
    assert!(body(&session, sweeper).unwrap().hp <= 0);

    // Broken sight snaps it: the Auditor is behind the pillar.
    let (mut session, participant) = fixture();
    let auditor = enemy(&session, "auditor");
    let sweeper = enemy(&session, "sweeper_a");
    disable(&mut session, participant, sweeper);
    until_channel(&mut session, auditor, participant);
    set(&mut session, auditor, -11.0, 5.0);
    set(&mut session, sweeper, -11.0, 9.5);
    advance(&mut session, 1);
    assert_eq!(phase(&session, auditor), EnemyPhase::Recovery);
    assert_eq!(auditor_state(&session).repairs_left, 2);

    // A body that leaves the world snaps it.
    let (mut session, participant) = fixture();
    let auditor = enemy(&session, "auditor");
    let sweeper = enemy(&session, "sweeper_a");
    disable(&mut session, participant, sweeper);
    until_channel(&mut session, auditor, participant);
    session.state.players.retain(|p| p.id != sweeper);
    advance(&mut session, 1);
    assert_eq!(phase(&session, auditor), EnemyPhase::Recovery);
    assert_eq!(auditor_state(&session).repairs_left, 2);

    // Standing on the disabled body at the last tick blocks the repair.
    let (mut session, participant) = fixture();
    let auditor = enemy(&session, "auditor");
    let sweeper = enemy(&session, "sweeper_a");
    disable(&mut session, participant, sweeper);
    until_channel(&mut session, auditor, participant);
    let (x, z) = {
        let body = body(&session, sweeper).unwrap();
        (body.x, body.z)
    };
    let other = enemy(&session, "clerk");
    set(&mut session, other, x + 0.4, z);
    while phase(&session, auditor) == EnemyPhase::Channeling {
        set(&mut session, other, x + 0.4, z);
        advance(&mut session, 1);
        heal(&mut session, participant);
    }
    assert!(
        body(&session, sweeper).is_none_or(|b| b.hp <= 0),
        "never stood up"
    );
    assert_eq!(phase(&session, auditor), EnemyPhase::Recovery);
    assert_eq!(auditor_state(&session).repairs_left, 2);
}

#[test]
fn a_disabled_clerk_is_a_person_and_is_never_repaired() {
    let (mut session, participant) = fixture();
    let auditor = enemy(&session, "auditor");
    let clerk = enemy(&session, "clerk");
    disable(&mut session, participant, clerk);
    for _ in 0..60 {
        advance(&mut session, 1);
        heal(&mut session, participant);
        assert_ne!(phase(&session, auditor), EnemyPhase::Channeling);
    }
    assert!(body(&session, clerk).is_none());
    assert_eq!(auditor_state(&session).repairs_left, 2);
}

#[test]
fn the_plate_halves_frontal_shots_but_not_a_flank_or_a_blast() {
    let (mut session, participant) = fixture();
    let auditor = enemy(&session, "auditor");
    // Freeze the officer facing -z so the plate points at the screen.
    let face = |session: &mut GameSession| {
        let player = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == auditor)
            .unwrap();
        player.x = 0.0;
        player.z = 8.0;
        player.yaw = -std::f32::consts::FRAC_PI_2;
        player.hp = 120;
        player.pending_action = Action::default();
    };
    face(&mut session);
    set(&mut session, participant, 0.0, 4.0);
    shoot(&mut session, participant, auditor, WeaponType::Tack);
    assert_eq!(
        body(&session, auditor).unwrap().hp,
        110,
        "half of 20 from the front"
    );
    face(&mut session);
    set(&mut session, participant, 0.0, 12.0);
    shoot(&mut session, participant, auditor, WeaponType::Tack);
    assert_eq!(
        body(&session, auditor).unwrap().hp,
        100,
        "full 20 from behind"
    );
    face(&mut session);
    set(&mut session, participant, 4.0, 8.0);
    shoot(&mut session, participant, auditor, WeaponType::Tack);
    assert_eq!(
        body(&session, auditor).unwrap().hp,
        100,
        "full 20 from the side"
    );
    // A blast centred in front wraps the plate.
    face(&mut session);
    set(&mut session, participant, 0.0, -6.0);
    let owner = participant;
    let before = body(&session, auditor).unwrap().hp;
    let feet = [0.0, 0.0, 6.5];
    let expected = (100.0 * (1.0 - (1.5 - crate::movement::RADIUS) / 4.0)).floor() as i32;
    session
        .state
        .test_blast(owner, [feet[0], 0.5, feet[2]], 4.0, 100.0);
    assert_eq!(body(&session, auditor).unwrap().hp, before - expected);
}

#[test]
fn a_party_wipe_resets_the_bay_and_restores_the_repair_budget() {
    let (mut session, participant) = fixture();
    let auditor = enemy(&session, "auditor");
    let sweeper = enemy(&session, "sweeper_a");
    disable(&mut session, participant, sweeper);
    until_channel(&mut session, auditor, participant);
    while phase(&session, auditor) == EnemyPhase::Channeling {
        advance(&mut session, 1);
        heal(&mut session, participant);
    }
    assert_eq!(auditor_state(&session).repairs_left, 1);
    if let Some(player) = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == participant)
    {
        player.hp = 0;
        player.respawn_timer = Some(60);
    }
    advance(&mut session, 2);
    if let Some(player) = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == participant)
    {
        player.hp = 100;
        player.respawn_timer = None;
    }
    advance(&mut session, 2);
    let state = auditor_state(&session);
    assert_eq!(state.repairs_left, 2);
    assert_ne!(state.id, auditor, "a fresh Auditor stands in the bay");
}

fn range() -> (GameSession, Uuid) {
    let map =
        AuthoredMap::read(include_bytes!("../../maps/test/custody-range.json").as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    assert_eq!(session.state.map.id(), 1014);
    assert!(session.state.map.has_custody_devices());
    session.state.seed(8);
    let participant = Uuid::from_u128(0x1014);
    session
        .state
        .add_player(participant, "Visitor".into(), Role::Human);
    advance(&mut session, 2);
    (session, participant)
}

fn face(session: &mut GameSession, id: Uuid, x: f32, z: f32, yaw: f32) {
    set(session, id, x, z);
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.yaw = yaw;
    player.pitch = 0.0;
}

#[test]
fn a_range_post_sweeper_walks_into_the_placed_mine() {
    let (mut session, participant) = range();
    // Take the cage mines: entering the alcove dispatches the post pair.
    face(&mut session, participant, -19.5, -0.5, 0.0);
    advance(&mut session, 2);
    let carried = session
        .state
        .players
        .iter()
        .find(|p| p.id == participant)
        .unwrap()
        .inventory
        .mines();
    assert_eq!(carried, 4);
    let posts: Vec<Uuid> = ["post_sweeper_a", "post_sweeper_b"]
        .into_iter()
        .map(|name| enemy(&session, name))
        .collect();
    // Throw one into the corridor mouth, then step back into the corner the
    // corridor cannot see.
    face(&mut session, participant, -16.0, 1.5, 0.0);
    session.state.set_action(
        participant,
        Action {
            place_mine: true,
            ..Default::default()
        },
    );
    advance(&mut session, 1);
    session.state.set_action(participant, Action::default());
    face(&mut session, participant, -19.5, 2.0, 0.0);
    let mut blast = None;
    for _ in 0..900 {
        advance(&mut session, 1);
        heal(&mut session, participant);
        face(&mut session, participant, -19.5, 2.0, 0.0);
        if let Some(found) = session
            .state
            .snapshot()
            .explosions
            .into_iter()
            .find(|e| e.owner_id == participant)
        {
            blast = Some(found);
            break;
        }
    }
    let blast = blast.expect("a post Sweeper walked into the mine");
    assert!(blast
        .hits
        .iter()
        .any(|hit| posts.contains(&hit.target_id) && hit.killed));
    let record = session.state.player_record(participant).unwrap();
    assert_eq!(record.total.mines.attacks, 1);
    assert!(record.total.mines.kills >= 1);
}

#[test]
fn the_range_bay_auditor_reaches_a_disabled_sweeper() {
    let (mut session, participant) = range();
    face(&mut session, participant, 4.0, 6.0, 1.5707964);
    advance(&mut session, 2);
    let auditor = enemy(&session, "bay_auditor");
    let sweeper = enemy(&session, "bay_sweeper_a");
    disable(&mut session, participant, sweeper);
    set(&mut session, participant, 0.0, -18.0);
    until_channel(&mut session, auditor, participant);
    assert_eq!(auditor_state(&session).channel_target, Some(sweeper));
}
