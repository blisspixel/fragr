//! Surveyor: seeded tick tests of the lens tell, the tracking disc, its
//! counters (sight, distance, a hit through the open lens), the shutter's
//! traced-damage rule and machine convergence on the disc.
use crate::encounters::enemy::attack_timing;
use crate::encounters::enemy::surveyor::{disc_speed, mark_ticks, MARK_SIGHT_GRACE};
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, LookAt, Role, WeaponType,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::json;
use uuid::Uuid;

const FACING_SOUTH: f32 = 4.712389;

/// A Surveyor 24 m north of an open participant, a wall to break sight
/// behind and, optionally, one absorbed Sweeper off to the west facing away.
fn yard(sweeper: bool) -> (GameSession, Uuid, Uuid) {
    yard_facing(sweeper.then_some("absorbed"), FACING_SOUTH)
}

/// The yard with the Sweeper under `sweeper` control, if any.
fn yard_facing(sweeper: Option<&str>, facing: f32) -> (GameSession, Uuid, Uuid) {
    let mut enemies = vec![
        json!({"id":"lens","kind":"surveyor","control":"restoration","feet":[0,0,24],"yaw":facing}),
    ];
    if let Some(control) = sweeper {
        enemies.push(
            json!({"id":"walker","kind":"sweeper","control":control,"feet":[-16,0,0],"yaw":std::f32::consts::PI}),
        );
    }
    let doc = json!({
        "version":1,"map_id":1000,"name":"Survey yard","half_extent":40,
        "ground":"concrete","equipment":"discovery",
        "solids":[
            {"id":"blind","min":[6,0,4],"max":[9,4,12],"surface":"concrete"},
            {"id":"screen","min":[-12,0,-5],"max":[-10,4,5],"surface":"concrete"}
        ],
        "spawns":[{"id":"entry","feet":[0,0,0],"yaw":1.5707964}],
        "landmarks":[{"id":"behind_blind","feet":[11,0,8]}],
        "encounters":[{
            "id":"survey","regions":[{"min":[-40,0,-40],"max":[40,4,40]}],
            "enemies":enemies
        }]
    });
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(2020);
    let id = Uuid::from_u128(2020);
    session.state.add_player(id, "Observed".into(), Role::Human);
    advance(&mut session, 1);
    place(&mut session, id, 0.0, 0.0);
    let lens = session
        .state
        .players
        .iter()
        .find(|p| {
            matches!(
                p.campaign,
                Some(CampaignActor::Hostile {
                    kind: EnemyKind::Surveyor,
                    ..
                })
            )
        })
        .unwrap()
        .id;
    (session, id, lens)
}

fn advance(session: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        session.tick_messages(0.05);
    }
}

fn place(session: &mut GameSession, id: Uuid, x: f32, z: f32) {
    let p = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    p.x = x;
    p.y = PLAYER_FLOOR_Y;
    p.z = z;
    p.vy = 0.0;
    p.hp = p.hp.max(1);
}

fn phase(session: &GameSession, id: Uuid) -> (EnemyPhase, u64, u64) {
    match session
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .campaign
    {
        Some(CampaignActor::Hostile {
            phase,
            phase_started,
            phase_ends,
            ..
        }) => (phase, phase_started, phase_ends),
        other => panic!("not a hostile body: {other:?}"),
    }
}

fn until_phase(session: &mut GameSession, lens: Uuid, wanted: EnemyPhase, limit: usize) {
    for _ in 0..limit {
        if phase(session, lens).0 == wanted {
            return;
        }
        advance(session, 1);
    }
    panic!(
        "Surveyor never reached {wanted:?}: {:?}",
        phase(session, lens)
    );
}

fn hp(session: &GameSession, id: Uuid) -> i32 {
    session
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .hp
}

fn shoot(session: &mut GameSession, shooter: Uuid, target: Uuid) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == shooter)
        .unwrap();
    player.inventory.grant_weapon(WeaponType::Rail);
    player
        .inventory
        .grant_ammo(crate::protocol::AmmoPool::Cells, 20);
    player.weapon = WeaponType::Rail;
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
    session.tick_messages(0.05);
    session.state.set_action(shooter, Action::default());
}

#[test]
fn lens_tell_then_disc_tracks_the_participant_below_walking_speed() {
    let (mut s, id, lens) = yard(false);
    until_phase(&mut s, lens, EnemyPhase::Windup, 80);
    let (_, start, end) = phase(&s, lens);
    let (windup, _) = attack_timing(EnemyKind::Surveyor, CampaignDifficulty::Standard);
    assert_eq!(end - start, windup, "the lens opening is the whole tell");
    assert!(windup >= 28, "every tier keeps a readable tell");
    assert!(s.state.snapshot().surveyor_marks.is_empty(), "no disc yet");
    until_phase(&mut s, lens, EnemyPhase::Firing, windup as usize + 4);
    let marks = s.state.snapshot().surveyor_marks;
    assert_eq!(marks.len(), 1);
    let mark = marks[0];
    mark.validate(40.0).unwrap();
    assert_eq!(mark.id, lens);
    assert!(mark.tracking);
    assert!(
        mark.center[0].hypot(mark.center[2]) < 0.5,
        "cast on the feet"
    );
    assert_eq!(
        mark.until - mark.since,
        mark_ticks(CampaignDifficulty::Standard)
    );
    // Walk east at full speed: the disc follows, slower than the walk.
    for _ in 0..20 {
        s.state.set_action(
            id,
            Action {
                right: true,
                yaw: Some(1.5707964),
                ..Default::default()
            },
        );
        advance(&mut s, 1);
    }
    let mark = s.state.snapshot().surveyor_marks[0];
    let me = s.state.players.iter().find(|p| p.id == id).unwrap();
    let travelled = mark.center[0].hypot(mark.center[2]);
    let speed = disc_speed(CampaignDifficulty::Standard);
    assert!(travelled > 0.5, "the disc tracks");
    assert!(
        travelled <= speed * 20.0 * 0.05 + 0.05,
        "the disc never outruns its speed"
    );
    assert!(
        (me.x - mark.center[0]).hypot(me.z - mark.center[2])
            > crate::protocol::SURVEYOR_MARK_RADIUS,
        "a walking participant steps off the disc"
    );
    // A disc that simply lapses is neither a success nor a broken mark.
    s.state.set_action(id, Action::default());
    place(&mut s, id, 0.0, 0.0);
    advance(
        &mut s,
        mark_ticks(CampaignDifficulty::Standard) as usize + 2,
    );
    assert_eq!(s.state.encounters.drain_marks_broken(), 0);
}

#[test]
fn breaking_sight_lapses_the_disc_and_counts_as_a_broken_mark() {
    let (mut s, id, lens) = yard(false);
    until_phase(&mut s, lens, EnemyPhase::Firing, 120);
    // Behind the blind: the Surveyor cannot see the participant.
    place(&mut s, id, 11.0, 8.0);
    advance(&mut s, 1);
    let mark = s.state.snapshot().surveyor_marks[0];
    assert!(!mark.tracking, "an unseen participant stops the disc");
    advance(&mut s, MARK_SIGHT_GRACE as usize + 2);
    assert!(s.state.snapshot().surveyor_marks.is_empty());
    assert_eq!(phase(&s, lens).0, EnemyPhase::Recovery);
    assert_eq!(s.state.encounters.drain_marks_broken(), 1);
    assert_eq!(s.state.encounters.drain_marks_broken(), 0, "drained once");
}

#[test]
fn a_hit_through_the_open_lens_staggers_it_and_the_closed_shutter_turns_most_damage() {
    // Facing away, its lens stays closed: a Rail hit loses two thirds.
    let (mut s, id, lens) = yard_facing(None, 1.5707964);
    let before = hp(&s, lens);
    assert_eq!(phase(&s, lens).0, EnemyPhase::Idle);
    shoot(&mut s, id, lens);
    let closed = before - hp(&s, lens);
    assert_eq!(closed, (WeaponType::Rail.damage() + 2) / 3);
    assert!(
        !matches!(phase(&s, lens).0, EnemyPhase::Hit),
        "a closed shutter shrugs off a hit"
    );
    // Lens open: the whole hit lands and the observation is broken.
    let (mut s, id, lens) = yard(false);
    until_phase(&mut s, lens, EnemyPhase::Firing, 120);
    let before = hp(&s, lens);
    shoot(&mut s, id, lens);
    assert_eq!(before - hp(&s, lens), WeaponType::Rail.damage());
    assert_eq!(phase(&s, lens).0, EnemyPhase::Hit);
    assert!(s.state.snapshot().surveyor_marks.is_empty());
    assert_eq!(s.state.encounters.drain_marks_broken(), 1);
    // A second open-lens hit kills it: ninety health never sponges.
    until_phase(&mut s, lens, EnemyPhase::Windup, 240);
    shoot(&mut s, id, lens);
    assert!(hp(&s, lens) <= 0, "two open-lens Rail hits kill a Surveyor");
}

#[test]
fn nearby_machines_converge_on_the_disc_and_an_arrival_spends_the_mark() {
    let (mut s, id, lens) = yard(true);
    let walker = s
        .state
        .players
        .iter()
        .find(|p| {
            matches!(
                p.campaign,
                Some(CampaignActor::Hostile {
                    kind: EnemyKind::Sweeper,
                    ..
                })
            )
        })
        .unwrap()
        .id;
    // Keep the participant alive and still; the Sweeper is behind a screen.
    until_phase(&mut s, lens, EnemyPhase::Firing, 120);
    let mark = s.state.snapshot().surveyor_marks[0];
    let start = {
        let w = s.state.players.iter().find(|p| p.id == walker).unwrap();
        (w.x - mark.center[0]).hypot(w.z - mark.center[2])
    };
    let mut closest = start;
    let mut arrived = false;
    let mut converged = false;
    for _ in 0..mark_ticks(CampaignDifficulty::Standard) as usize - 4 {
        if let Some(p) = s.state.players.iter_mut().find(|p| p.id == id) {
            p.hp = 100;
            p.armor = 0;
        }
        advance(&mut s, 1);
        let Some(mark) = s.state.snapshot().surveyor_marks.first().copied() else {
            break;
        };
        converged |= s.state.encounters.converging(walker);
        let w = s.state.players.iter().find(|p| p.id == walker).unwrap();
        let distance = (w.x - mark.center[0]).hypot(w.z - mark.center[2]);
        closest = closest.min(distance);
        if distance <= crate::encounters::enemy::surveyor::ARRIVAL_RADIUS {
            arrived = true;
            break;
        }
    }
    assert!(closest < start - 6.0, "the Sweeper converges on the disc");
    assert!(arrived, "the Sweeper reaches the disc inside its lifetime");
    assert!(converged, "the absorbed Sweeper reads the restoration mark");
    // Striking the Surveyor after a machine arrived no longer breaks the mark.
    shoot(&mut s, id, lens);
    assert_eq!(s.state.encounters.drain_marks_broken(), 0);
}

#[test]
fn a_machine_still_answering_the_union_never_reads_a_restoration_mark() {
    let (mut s, id, lens) = yard_facing(Some("union"), FACING_SOUTH);
    let walker = s
        .state
        .players
        .iter()
        .find(|p| {
            matches!(
                p.campaign,
                Some(CampaignActor::Hostile {
                    kind: EnemyKind::Sweeper,
                    ..
                })
            )
        })
        .unwrap()
        .id;
    until_phase(&mut s, lens, EnemyPhase::Firing, 120);
    assert_eq!(s.state.snapshot().surveyor_marks.len(), 1);
    for _ in 0..80 {
        if let Some(p) = s.state.players.iter_mut().find(|p| p.id == id) {
            p.hp = 100;
            p.armor = 0;
        }
        advance(&mut s, 1);
        assert!(
            !s.state.encounters.converging(walker),
            "a Union Sweeper ignores the Inheritance's disc"
        );
    }
}

#[test]
fn every_tier_keeps_the_lens_tell_and_a_disc_slower_than_a_walk() {
    let mut previous: Option<(u64, f32)> = None;
    for difficulty in [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ] {
        let (windup, recovery) = attack_timing(EnemyKind::Surveyor, difficulty);
        let speed = disc_speed(difficulty);
        assert!(windup >= 28 && recovery >= 40);
        assert!(speed < crate::movement::TOP_SPEED * 0.6);
        assert!(mark_ticks(difficulty) >= 120);
        if let Some((tell, pace)) = previous {
            assert!(windup < tell, "harder tiers open faster");
            assert!(speed > pace, "harder tiers track faster");
        }
        previous = Some((windup, speed));
    }
    let (body, weapon) = crate::encounters::enemy::body(EnemyKind::Surveyor);
    assert_eq!(
        (body, weapon),
        (90, WeaponType::Fists),
        "a spotter never fires"
    );
    assert_eq!(crate::encounters::enemy::gait(EnemyKind::Surveyor), 0.0);
}
