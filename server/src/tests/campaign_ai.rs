//! Campaign guards, squad roles and chatter: seeded tick tests through the
//! real session. The authored region stays the alarm; each guard then needs
//! its own sighting (a 120 degree cone, a level gaze, cover) and a 200 to
//! 400 ms reaction before it attacks, and turns toward the alarm first if it
//! has not seen anyone. Skirmishers go around while an anchor fires; the Heavy
//! pins a lane; chatter is rare and spaced.
use crate::maps::AuthoredMap;
use crate::protocol::{
    Action, BarkRegister, CampaignActor, CompanionBarkKind, EnemyBarkKind, EnemyKind, EnemyPhase,
    GameEvent, LookAt, Role, ServerMessage, WeaponType,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::{json, Value};
use std::f32::consts::{FRAC_PI_2, PI};
use uuid::Uuid;

/// Facing toward negative z: toward the spawn in these fixtures.
const TOWARD_SPAWN: f32 = 3.0 * FRAC_PI_2;
/// Facing toward positive z: away from the spawn.
const AWAY: f32 = FRAC_PI_2;

fn session(enemies: Value, solids: Value, region: Value) -> (GameSession, Uuid) {
    let doc = json!({
        "version":1,"map_id":1000,"name":"Campaign AI fixture","half_extent":24,
        "ground":"concrete","equipment":"discovery","solids":solids,
        "spawns":[{"id":"entry","feet":[0,0,-10],"yaw":FRAC_PI_2}],
        "landmarks":[{"id":"exit","feet":[0,0,20]}],
        "encounters":[{"id":"post","regions":[region],"enemies":enemies}]
    });
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.seed(42);
    // Numbered bodies, so each guard's reaction repeats exactly.
    session.state.use_replay_ids();
    let id = Uuid::from_u128(100);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    (session, id)
}

/// The room around the clerk at z 8, from z 2 to 14.
fn room() -> Value {
    json!({"min":[-6,0,2],"max":[6,8,14]})
}

/// A region nobody in these fixtures enters.
fn far_region() -> Value {
    json!({"min":[20,0,20],"max":[23,2,23]})
}

/// Ticks until `guard` raises its gun, within `limit`.
fn raise(session: &mut GameSession, guard: Uuid, limit: usize) -> Option<usize> {
    for tick in 1..=limit {
        advance(session, 1);
        if phase(session, guard) == EnemyPhase::Windup {
            return Some(tick);
        }
    }
    None
}

fn advance(session: &mut GameSession, ticks: usize) -> Vec<GameEvent> {
    let mut events = Vec::new();
    for _ in 0..ticks {
        for message in session.tick_messages(0.05) {
            if let ServerMessage::Event(event) = message {
                events.push(event);
            }
        }
    }
    events
}

fn guard(session: &GameSession, kind: EnemyKind) -> Uuid {
    session
        .state
        .players
        .iter()
        .find(|p| matches!(p.campaign, Some(CampaignActor::Hostile { kind: k, .. }) if k == kind))
        .unwrap()
        .id
}

fn phase(session: &GameSession, id: Uuid) -> EnemyPhase {
    match session
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .campaign
    {
        Some(CampaignActor::Hostile { phase, .. }) => phase,
        _ => panic!("expected an enemy"),
    }
}

fn body(session: &GameSession, id: Uuid) -> &crate::sim::Player {
    session.state.players.iter().find(|p| p.id == id).unwrap()
}

fn place(session: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.x = feet[0];
    player.y = feet[1] + PLAYER_FLOOR_Y;
    player.z = feet[2];
    player.vy = 0.0;
}

fn sightings(events: &[GameEvent]) -> Vec<(EnemyBarkKind, BarkRegister)> {
    events
        .iter()
        .filter_map(|event| match event {
            GameEvent::EnemyBark { kind, register, .. } => Some((*kind, *register)),
            _ => None,
        })
        .collect()
}

/// Advance one tick at a time and count the shots `id` resolves.
fn shots_over(session: &mut GameSession, ticks: usize, id: Uuid) -> usize {
    let mut shots = 0;
    for _ in 0..ticks {
        advance(session, 1);
        shots += session
            .state
            .shot_results
            .iter()
            .filter(|shot| shot.shooter_id == id)
            .count();
    }
    shots
}

#[test]
fn a_guard_on_post_waits_for_its_region_even_with_the_party_in_view() {
    let (mut session, id) = session(
        json!([{"id":"clerk","kind":"clerk","feet":[0,0,8],"yaw":TOWARD_SPAWN}]),
        json!([]),
        room(),
    );
    // In plain view a metre outside the room: the authored alarm has not
    // sounded, so the room stays as written.
    place(&mut session, id, [0.0, 0.0, 1.0]);
    let events = advance(&mut session, 60);
    assert!(!session.state.encounters.is_awake(0));
    assert!(sightings(&events).is_empty());
    // One step in: the clerk, already facing the door, reacts after 200 to
    // 400 ms and calls the sighting once on Union radio.
    place(&mut session, id, [0.0, 0.0, 3.0]);
    let clerk = guard(&session, EnemyKind::Clerk);
    let mut events = Vec::new();
    let mut raised = None;
    for tick in 1..=20 {
        events.extend(advance(&mut session, 1));
        if raised.is_none() && phase(&session, clerk) == EnemyPhase::Windup {
            raised = Some(tick);
        }
    }
    let raised = raised.expect("a clerk facing the door raises");
    assert!(
        raised <= 2,
        "a clerk already looking at the door was expecting someone: {raised}"
    );
    assert_eq!(
        sightings(&events),
        vec![(EnemyBarkKind::Sighting, BarkRegister::Personnel)]
    );
    assert!(shots_over(&mut session, 60, clerk) > 0, "and then fights");
}

#[test]
fn cover_and_an_overhead_ambush_hold_off_an_alarmed_guard() {
    // A shelf four metres in front of the clerk, six metres up, inside the
    // room. (Cover is the shared line-of-sight gate; a guard behind a wall
    // walks to the alarm as it always has.)
    let solids = json!([
        {"id":"shelf","min":[-1,0,3],"max":[1,6,5],"surface":"enamel"}
    ]);
    let enemies = json!([{"id":"clerk","kind":"clerk","feet":[0,0,8],"yaw":TOWARD_SPAWN}]);
    // Overhead the clerk never sees them before its alarm bound.
    for (feet, why, held) in [(
        [0.0, 6.0, 4.0],
        "a body overhead is outside a level gaze",
        18,
    )] {
        let (mut session, id) = session(enemies.clone(), solids.clone(), room());
        place(&mut session, id, feet);
        advance(&mut session, 1);
        assert!(session.state.encounters.is_awake(0));
        let clerk = guard(&session, EnemyKind::Clerk);
        for _ in 0..held {
            place(&mut session, id, feet);
            advance(&mut session, 1);
            assert_ne!(phase(&session, clerk), EnemyPhase::Windup, "{why}");
            assert!(!session.state.encounters.aware(clerk), "{why}");
        }
    }
    // In the open inside its cone it sees them.
    let (mut session, id) = session(enemies, solids, room());
    place(&mut session, id, [3.0, 0.0, 6.0]);
    advance(&mut session, 1);
    let clerk = guard(&session, EnemyKind::Clerk);
    let raised = raise(&mut session, clerk, 20).expect("in the open the clerk sees them");
    assert!(raised <= 10, "{raised}");
}

#[test]
fn an_alarmed_guard_that_never_sees_anyone_still_joins_the_fight() {
    // The participant hides overhead; after the alarm bound the clerk fights
    // as it did before guards needed a sighting.
    let (mut session, id) = session(
        json!([{"id":"clerk","kind":"clerk","feet":[0,0,8],"yaw":TOWARD_SPAWN}]),
        json!([{"id":"shelf","min":[-1,0,3],"max":[1,6,5],"surface":"enamel"}]),
        room(),
    );
    place(&mut session, id, [0.0, 6.0, 4.0]);
    advance(&mut session, 1);
    let clerk = guard(&session, EnemyKind::Clerk);
    for _ in 0..18 {
        place(&mut session, id, [0.0, 6.0, 4.0]);
        advance(&mut session, 1);
    }
    assert!(!session.state.encounters.aware(clerk));
    place(&mut session, id, [0.0, 6.0, 4.0]);
    advance(&mut session, 2);
    assert!(
        session.state.encounters.aware(clerk),
        "one second after the alarm the room is in the fight"
    );
}
#[test]
fn entering_a_region_behind_a_guard_buys_the_first_shots_then_it_turns() {
    let region = json!({"min":[-6,0,-6],"max":[6,2,14]});
    let (mut front, front_id) = session(
        json!([{"id":"clerk","kind":"clerk","feet":[0,0,8],"yaw":TOWARD_SPAWN}]),
        json!([]),
        region.clone(),
    );
    let (mut back, back_id) = session(
        json!([{"id":"clerk","kind":"clerk","feet":[0,0,8],"yaw":AWAY}]),
        json!([]),
        region,
    );
    // Seen from the front by a clerk already looking at the door: it raises
    // at once, as it always has.
    place(&mut front, front_id, [0.0, 0.0, 4.0]);
    advance(&mut front, 1);
    let front_clerk = guard(&front, EnemyKind::Clerk);
    let mut front_raise = None;
    for tick in 1..=30 {
        advance(&mut front, 1);
        if phase(&front, front_clerk) == EnemyPhase::Windup {
            front_raise = Some(tick);
            break;
        }
    }
    let front_raise = front_raise.expect("a facing clerk raises");
    assert!(front_raise <= 2, "{front_raise}");

    // Entering behind it: the region wakes the group, but the clerk has heard
    // an alarm, not seen anyone. It turns toward it before it can react.
    place(&mut back, back_id, [0.0, 0.0, 4.0]);
    advance(&mut back, 1);
    assert!(back.state.encounters.is_awake(0));
    let back_clerk = guard(&back, EnemyKind::Clerk);
    let start_yaw = body(&back, back_clerk).yaw;
    let mut back_raise = None;
    for tick in 1..=60 {
        advance(&mut back, 1);
        if phase(&back, back_clerk) == EnemyPhase::Windup {
            back_raise = Some(tick);
            break;
        }
    }
    let back_raise = back_raise.expect("the clerk joins the fight within its bound");
    assert!(
        back_raise >= front_raise + 8,
        "behind it the participant gets the first shots: {back_raise} vs {front_raise}"
    );
    assert!(
        back_raise <= 22,
        "the alarm bound keeps the room in the fight"
    );
    let turned = body(&back, back_clerk).yaw;
    assert!(
        ((turned - start_yaw + PI).rem_euclid(2.0 * PI) - PI).abs() > 2.0,
        "the clerk turned around: {start_yaw} to {turned}"
    );
}

#[test]
fn a_shot_that_strikes_one_guard_puts_its_whole_group_in_the_fight() {
    let (mut session, id) = session(
        json!([
            {"id":"a","kind":"clerk","feet":[-2,0,8],"yaw":AWAY},
            {"id":"b","kind":"clerk","feet":[2,0,8],"yaw":AWAY}
        ]),
        json!([]),
        far_region(),
    );
    advance(&mut session, 1);
    let clerks: Vec<Uuid> = session
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| p.id)
        .collect();
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.inventory.grant_weapon(WeaponType::Tack);
    player.weapon = WeaponType::Tack;
    player.fire_cooldown = 0;
    session.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(clerks[0]),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    session.state.set_action(id, Action::default());
    assert!(session.state.encounters.is_awake(0));
    assert!(
        session.state.encounters.aware(clerks[0]),
        "struck, it knows"
    );
    assert!(
        session.state.encounters.aware(clerks[1]),
        "gunfire in the room: its peer needs no sighting"
    );
}

#[test]
fn a_skirmisher_goes_around_while_the_heavy_holds_the_lane() {
    let region = json!({"min":[-20,0,-20],"max":[20,2,20]});
    let (mut session, id) = session(
        json!([
            {"id":"heavy","kind":"heavy_sweeper","feet":[0,0,10],"yaw":TOWARD_SPAWN},
            {"id":"sweeper","kind":"sweeper","feet":[1.5,0,11],"yaw":TOWARD_SPAWN}
        ]),
        json!([]),
        region,
    );
    place(&mut session, id, [0.0, 0.0, 0.0]);
    advance(&mut session, 1);
    let heavy = guard(&session, EnemyKind::HeavySweeper);
    let sweeper = guard(&session, EnemyKind::Sweeper);
    // The heavy's tell is the anchor.
    for _ in 0..40 {
        if matches!(
            phase(&session, heavy),
            EnemyPhase::Windup | EnemyPhase::Firing
        ) {
            break;
        }
        advance(&mut session, 1);
    }
    assert!(matches!(
        phase(&session, heavy),
        EnemyPhase::Windup | EnemyPhase::Firing
    ));
    let angle = |session: &GameSession| {
        let h = body(session, heavy);
        let s = body(session, sweeper);
        let lane = h.z.atan2(h.x);
        let me = s.z.atan2(s.x);
        ((me - lane + PI).rem_euclid(2.0 * PI) - PI).abs()
    };
    let before = angle(&session);
    let mut widest = before;
    for _ in 0..150 {
        // Hold the participant still and at full health so the room keeps
        // fighting the same body.
        session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap()
            .hp = 100;
        place(&mut session, id, [0.0, 0.0, 0.0]);
        advance(&mut session, 1);
        widest = widest.max(angle(&session));
    }
    assert!(before < 0.3, "{before}");
    assert!(
        widest >= 0.6,
        "the sweeper left the heavy's line: {before} to {widest}"
    );
}

/// A Crawler is a leaper, not a gun: it never walks a flank, which would take
/// it out to six metres or more and past its four metre leap. While the
/// heavy holds the lane, a Crawler inside leap range leaps.
#[test]
fn a_crawler_leaps_while_the_heavy_holds_the_lane_and_never_flanks() {
    let region = json!({"min":[-20,0,-20],"max":[20,2,20]});
    let (mut session, id) = session(
        json!([
            {"id":"heavy","kind":"heavy_sweeper","feet":[0,0,10],"yaw":TOWARD_SPAWN},
            {"id":"crawler","kind":"crawler","feet":[0.5,0,14],"yaw":TOWARD_SPAWN}
        ]),
        json!([]),
        region,
    );
    place(&mut session, id, [0.0, 0.0, 0.0]);
    advance(&mut session, 1);
    let heavy = guard(&session, EnemyKind::HeavySweeper);
    let crawler = guard(&session, EnemyKind::Crawler);
    let hold = |session: &mut GameSession| {
        session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap()
            .hp = 100;
        place(session, id, [0.0, 0.0, 0.0]);
    };
    // The heavy's tell is the anchor; the Crawler waits out of reach.
    for _ in 0..40 {
        hold(&mut session);
        place(&mut session, crawler, [0.5, 0.0, 14.0]);
        if matches!(
            phase(&session, heavy),
            EnemyPhase::Windup | EnemyPhase::Firing
        ) {
            break;
        }
        advance(&mut session, 1);
    }
    assert!(matches!(
        phase(&session, heavy),
        EnemyPhase::Windup | EnemyPhase::Firing
    ));
    // In the heavy's lane, inside leap range.
    place(&mut session, crawler, [0.3, 0.0, 3.0]);
    let mut leapt = false;
    let mut flanked = false;
    let mut farthest: f32 = 0.0;
    for _ in 0..30 {
        hold(&mut session);
        let events = advance(&mut session, 1);
        flanked |= events.iter().any(|event| {
            matches!(
                event,
                GameEvent::EnemyBark {
                    kind: EnemyBarkKind::Flanking,
                    speaker_id,
                    ..
                } if *speaker_id == crawler
            )
        });
        let c = body(&session, crawler);
        farthest = farthest.max(c.x.hypot(c.z));
        if matches!(
            phase(&session, crawler),
            EnemyPhase::Windup | EnemyPhase::Leaping
        ) {
            leapt = true;
            break;
        }
    }
    assert!(!flanked, "a Crawler never calls a flank");
    assert!(
        leapt,
        "a Crawler inside leap range leaps while the heavy holds the lane; it went out to {farthest} m"
    );
    assert!(farthest < 4.0, "it never left leap range: {farthest} m");
}

#[test]
fn a_heavy_burst_finishes_down_its_lane_into_the_cover() {
    let region = json!({"min":[-20,0,-20],"max":[20,2,20]});
    let (mut session, id) = session(
        json!([{"id":"heavy","kind":"heavy_sweeper","feet":[0,0,8],"yaw":TOWARD_SPAWN}]),
        json!([{"id":"cover","min":[2,0,-1],"max":[7,3,1],"surface":"enamel"}]),
        region,
    );
    place(&mut session, id, [1.0, 0.0, 0.0]);
    advance(&mut session, 1);
    let heavy = guard(&session, EnemyKind::HeavySweeper);
    let mut first = false;
    for _ in 0..80 {
        session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap()
            .hp = 100;
        if shots_over(&mut session, 1, heavy) > 0 {
            first = true;
            break;
        }
    }
    assert!(first, "the heavy opened its burst");
    assert_eq!(phase(&session, heavy), EnemyPhase::Firing);
    // Step behind the cover: the burst keeps coming down the committed lane.
    place(&mut session, id, [4.5, 0.0, -3.0]);
    let mut rest = 0;
    for _ in 0..20 {
        session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap()
            .hp = 100;
        rest += shots_over(&mut session, 1, heavy);
    }
    assert_eq!(rest, 3, "all four rounds of the burst were fired");
}

#[test]
fn an_auditor_down_is_called_by_the_unit_beside_it() {
    let region = json!({"min":[-20,0,-20],"max":[20,2,20]});
    let (mut session, id) = session(
        json!([
            {"id":"auditor","kind":"auditor","feet":[0,0,8],"yaw":AWAY},
            {"id":"sweeper","kind":"sweeper","feet":[3,0,9],"yaw":AWAY}
        ]),
        json!([]),
        far_region(),
    );
    let _ = region;
    advance(&mut session, 1);
    let auditor = guard(&session, EnemyKind::Auditor);
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == auditor)
        .unwrap()
        .hp = 1;
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    player.inventory.grant_weapon(WeaponType::Tack);
    player.weapon = WeaponType::Tack;
    player.fire_cooldown = 0;
    session.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(auditor),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    session.state.set_action(id, Action::default());
    assert!(body(&session, auditor).hp <= 0);
    let events = advance(&mut session, 2);
    assert_eq!(
        sightings(&events),
        vec![(EnemyBarkKind::OfficerDown, BarkRegister::Unit)],
        "the sweeper recites its boilerplate"
    );
    // Equipment and the dead say nothing more in the next five seconds.
    assert!(sightings(&advance(&mut session, 99)).is_empty());
}

/// Latch beside the participant, as the companion identity the barks read.
fn add_latch(session: &mut GameSession, feet: [f32; 3]) -> Uuid {
    let latch = Uuid::from_u128(200);
    session.state.add_player(latch, "Latch".into(), Role::Agent);
    let body = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == latch)
        .unwrap();
    body.campaign = Some(CampaignActor::Companion {
        kind: crate::protocol::CompanionKind::Latch,
        phase: crate::protocol::CompanionPhase::Following,
        phase_started: 0,
    });
    body.hp = 100;
    place(session, latch, feet);
    latch
}

fn callouts(events: &[GameEvent]) -> Vec<(CompanionBarkKind, Option<EnemyKind>)> {
    events
        .iter()
        .filter_map(|event| match event {
            GameEvent::CompanionBark { kind, subject, .. } => Some((*kind, *subject)),
            _ => None,
        })
        .collect()
}

#[test]
fn latch_calls_a_charging_turret_and_a_gun_behind_the_participant() {
    let region = json!({"min":[-20,0,-20],"max":[20,2,20]});
    let (mut turret, id) = session(
        json!([{"id":"turret","kind":"turret","feet":[0,0,8],"yaw":TOWARD_SPAWN}]),
        json!([]),
        region.clone(),
    );
    place(&mut turret, id, [0.0, 0.0, 0.0]);
    let latch = add_latch(&mut turret, [2.0, 0.0, -1.0]);
    let mut events = Vec::new();
    for _ in 0..60 {
        turret
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap()
            .hp = 100;
        events.extend(advance(&mut turret, 1));
    }
    let calls = callouts(&events);
    assert_eq!(
        calls,
        vec![(CompanionBarkKind::PriorityTarget, Some(EnemyKind::Turret))],
        "one callout for the turret's charge"
    );
    assert!(events.iter().any(|event| matches!(
        event,
        GameEvent::CompanionBark { speaker_id, .. } if *speaker_id == latch
    )));

    // A clerk behind the participant's shoulder raises its gun.
    let (mut behind, id) = session(
        json!([{"id":"clerk","kind":"clerk","feet":[0,0,-8],"yaw":FRAC_PI_2}]),
        json!([]),
        region,
    );
    place(&mut behind, id, [0.0, 0.0, 0.0]);
    behind
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .yaw = FRAC_PI_2;
    add_latch(&mut behind, [2.0, 0.0, 1.0]);
    let mut events = Vec::new();
    for _ in 0..40 {
        behind
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap()
            .hp = 100;
        events.extend(advance(&mut behind, 1));
    }
    assert!(
        callouts(&events).contains(&(CompanionBarkKind::FlankWarning, None)),
        "{:?}",
        callouts(&events)
    );
    // The clerk's sighting and Latch's warning both get through: Latch may
    // cut across Union radio.
    assert!(sightings(&events).contains(&(EnemyBarkKind::Sighting, BarkRegister::Personnel)));
}

#[test]
fn bark_events_have_a_strict_wire_shape() {
    let enemy = GameEvent::EnemyBark {
        kind: EnemyBarkKind::OfficerDown,
        register: BarkRegister::Unit,
        variant: 2,
        speaker_id: Uuid::from_u128(7),
        position: [1.0, 0.0, -2.0],
    };
    let wire = serde_json::to_value(ServerMessage::Event(enemy)).unwrap();
    assert_eq!(
        wire,
        json!({"type":"event","event":"enemy_bark","kind":"officer_down","register":"unit",
            "variant":2,"speaker_id":"00000000-0000-0000-0000-000000000007","position":[1.0,0.0,-2.0]})
    );
    let latch = GameEvent::CompanionBark {
        kind: CompanionBarkKind::FlankWarning,
        subject: None,
        variant: 0,
        speaker_id: Uuid::from_u128(8),
        position: [0.0, 0.0, 0.0],
    };
    let wire = serde_json::to_value(&latch).unwrap();
    assert!(wire.get("subject").is_none(), "absent subject is omitted");
    assert_eq!(wire["event"], "companion_bark");
    assert_eq!(wire["kind"], "flank_warning");
    let priority = json!({"event":"companion_bark","kind":"priority_target","subject":"auditor",
        "variant":1,"speaker_id":"00000000-0000-0000-0000-000000000008","position":[0,0,0]});
    assert!(matches!(
        serde_json::from_value::<GameEvent>(priority).unwrap(),
        GameEvent::CompanionBark {
            subject: Some(EnemyKind::Auditor),
            variant: 1,
            ..
        }
    ));
    let unknown = json!({"event":"enemy_bark","kind":"taunt","register":"unit","variant":0,
        "speaker_id":"00000000-0000-0000-0000-000000000007","position":[0,0,0]});
    assert!(serde_json::from_value::<GameEvent>(unknown).is_err());
}
