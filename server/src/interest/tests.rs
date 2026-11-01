use super::*;
use crate::movement::Solid;
use crate::protocol::{GameMode, Role, Team};
use crate::sim::PLAYER_FLOOR_Y;

/// A wall from z = -20 to z = 10 along x = 0: a corner at its north end.
fn wall() -> Vec<Solid> {
    vec![Solid::from_center_top(0.0, -5.0, 0.5, 15.0, 6.6)]
}

const READER: u128 = 1;
const TARGET: u128 = 2;

fn id(n: u128) -> Uuid {
    Uuid::from_u128(n)
}

/// A started round with fighters standing at `feet` (x, z), in id order.
fn state_with(positions: &[(f32, f32)]) -> GameState {
    let mut state = GameState::arsenal();
    state.seed(42);
    state.start_round();
    for (index, (x, z)) in positions.iter().enumerate() {
        let n = index as u128 + 1;
        state.add_player(id(n), format!("Probe {n}"), Role::Human);
        let player = state.players.last_mut().unwrap();
        player.x = *x;
        player.y = PLAYER_FLOOR_Y;
        player.z = *z;
    }
    state.spawn_shields.clear();
    state.tick = 10;
    state
}

fn player(state: &mut GameState, n: u128) -> &mut Player {
    state.players.iter_mut().find(|p| p.id == id(n)).unwrap()
}

fn sense_once(
    interest: &mut Interest,
    state: &GameState,
    reader: u128,
    target: u128,
    solids: &[Solid],
) -> Sense {
    let snapshot = state.snapshot();
    let views = interest.views_in(state, &snapshot, &[id(reader)], solids);
    let index = snapshot
        .players
        .iter()
        .position(|row| row.id == id(target))
        .expect("target row");
    views[&id(reader)]
        .rows
        .iter()
        .find(|(at, _)| *at == index)
        .map_or(Sense::Seen, |(_, sense)| *sense)
}

/// The sense after two ticks of tracing: the
/// tick before and this one, with the fighters where they stand now.
fn sense_of(
    interest: &mut Interest,
    state: &mut GameState,
    reader: u128,
    target: u128,
    solids: &[Solid],
) -> Sense {
    let tick = state.tick;
    state.tick = tick.saturating_sub(1);
    sense_once(interest, state, reader, target, solids);
    state.tick = tick;
    sense_once(interest, state, reader, target, solids)
}

/// What a reader with no margins would see: its eye straight to the
/// target's chest, now. The moment a body is really on screen.
fn truly_visible(state: &GameState, reader: u128, target: u128, solids: &[Solid]) -> bool {
    let r = state.players.iter().find(|p| p.id == id(reader)).unwrap();
    let t = state.players.iter().find(|p| p.id == id(target)).unwrap();
    crate::combat::line_of_sight(
        eye(r),
        crate::combat::aim_point_for(feet(t), t.campaign, t.ducking),
        solids,
    )
}

#[test]
fn a_fighter_behind_a_wall_is_hidden_and_its_row_is_inert() {
    let solids = wall();
    let mut state = state_with(&[(-5.0, 0.0), (5.0, 0.0)]);
    let mut interest = Interest::default();
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Hidden
    );
    // The same pair with no wall is seen.
    let mut open = Interest::default();
    assert_eq!(
        sense_of(&mut open, &mut state, READER, TARGET, &[]),
        Sense::Seen
    );

    let row = state
        .snapshot()
        .players
        .into_iter()
        .find(|row| row.id == id(TARGET))
        .unwrap();
    let hidden = redact(&row, Sense::Hidden);
    assert_eq!(hidden.sense, Some(PlayerSense::Hidden));
    assert_eq!((hidden.x, hidden.y, hidden.z), (0.0, 0.0, 0.0));
    assert_eq!(
        (hidden.hp, hidden.armor, hidden.yaw, hidden.pitch),
        (0, 0, 0.0, 0.0)
    );
    assert!(!hidden.collidable && !hidden.just_fired && !hidden.ducking);
    assert_eq!(hidden.weapon, "Fists");
    // Identity and the scoreboard stay.
    assert_eq!(
        (hidden.id, &hidden.name, hidden.score),
        (row.id, &row.name, row.score)
    );
    assert_eq!((hidden.body, hidden.dress), (row.body, row.dress));
    // A row the reader sees is untouched, and inert rows are no target.
    assert_eq!(redact(&row, Sense::Seen).sense, None);
    let reader_row = redact(&row, Sense::Seen);
    assert!(!reader_row.is_hostile_to(&hidden));
}

#[test]
fn a_fighter_rounding_the_corner_arrives_before_it_can_be_seen() {
    // The reader holds the corner from the north west; the target runs north
    // behind the wall and out past its end at z = 10.
    let solids = wall();
    for ping in [None, Some(50), Some(150)] {
        let mut state = state_with(&[(-10.0, 14.0), (3.0, 0.0)]);
        player(&mut state, READER).ping_ms = ping;
        let mut interest = Interest::default();
        let (mut sent, mut seen) = (None, None);
        for step in 0..60_u64 {
            state.tick = 100 + step;
            let target = player(&mut state, TARGET);
            target.z = step as f32 * 0.3;
            target.vz = crate::movement::TOP_SPEED;
            let sense = sense_once(&mut interest, &state, READER, TARGET, &solids);
            if sense == Sense::Seen && sent.is_none() {
                sent = Some(step);
            }
            if truly_visible(&state, READER, TARGET, &solids) && seen.is_none() {
                seen = Some(step);
            }
        }
        let (sent, seen) = (sent.unwrap(), seen.unwrap());
        assert!(sent > 0, "the target starts hidden");
        // The reader's client draws others 2 ticks behind and its world is
        // half a round trip old: the row must already be there.
        let needed = 2 + u64::from(ping.unwrap_or(0)) / 2 / 50 + 1;
        assert!(
            seen >= sent + needed,
            "ping {ping:?}: sent at {sent}, visible at {seen}, needs {needed} ticks"
        );
    }
}

#[test]
fn a_peek_reveals_the_holder_before_the_peeker_clears_the_corner() {
    // The target holds still past the wall; the reader strafes north out of
    // cover at full speed. Its own client predicts it a lead ahead.
    let solids = wall();
    for ping in [None, Some(100)] {
        let mut state = state_with(&[(-3.0, 4.0), (3.0, 0.0)]);
        player(&mut state, READER).ping_ms = ping;
        let mut interest = Interest::default();
        let (mut sent, mut seen) = (None, None);
        for step in 0..80_u64 {
            state.tick = 100 + step;
            let reader = player(&mut state, READER);
            reader.z = 4.0 + step as f32 * 0.3;
            reader.vz = crate::movement::TOP_SPEED;
            if sense_once(&mut interest, &state, READER, TARGET, &solids) == Sense::Seen
                && sent.is_none()
            {
                sent = Some(step);
            }
            if truly_visible(&state, READER, TARGET, &solids) && seen.is_none() {
                seen = Some(step);
            }
        }
        let (sent, seen) = (sent.unwrap(), seen.unwrap());
        let lead = lead_ticks(ping).floor() as u64;
        assert!(
            seen >= sent + lead,
            "ping {ping:?}: sent at {sent}, visible at {seen}, lead {lead}"
        );
    }
}

#[test]
fn a_sighting_is_kept_for_the_grace_and_then_withdrawn() {
    let solids = wall();
    let mut state = state_with(&[(-5.0, 0.0), (5.0, 30.0)]);
    let mut interest = Interest::default();
    state.tick = 50;
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Seen
    );
    player(&mut state, TARGET).z = 0.0;
    // The last line was traced at 49 or 50, whichever was the pair's tick.
    for tick in 51..=49 + SEEN_GRACE {
        state.tick = tick;
        assert_eq!(
            sense_of(&mut interest, &mut state, READER, TARGET, &solids),
            Sense::Seen,
            "tick {tick} is inside the grace"
        );
    }
    state.tick = 51 + SEEN_GRACE;
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Hidden
    );
}

#[test]
fn running_feet_are_heard_at_a_rough_place_and_a_walk_is_silent() {
    let solids = wall();
    let mut state = state_with(&[(-5.0, 0.0), (5.0, 0.0)]);
    let mut interest = Interest::default();
    state.tick = 10;
    player(&mut state, TARGET).vz = 2.0;
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Hidden,
        "a walk makes no sound"
    );
    player(&mut state, TARGET).vz = crate::movement::TOP_SPEED;
    state.tick = 11;
    let Sense::Heard(at) = sense_of(&mut interest, &mut state, READER, TARGET, &solids) else {
        panic!("running feet behind a wall are heard");
    };
    let off = (at[0] - 5.0).hypot(at[2]);
    assert!(off <= 10.0 * EAR_ERROR + 1e-4, "off by {off}");
    assert!(off > 0.0, "a sound never gives the exact place");
    // The place drifts a little from tick to tick rather than jumping.
    state.tick = 12;
    let Sense::Heard(next) = sense_of(&mut interest, &mut state, READER, TARGET, &solids) else {
        panic!("still running");
    };
    assert!((next[0] - at[0]).hypot(next[2] - at[2]) < 0.1);
    // Past the reach nothing is heard.
    let mut far = state_with(&[(-15.0, 0.0), (15.0, 0.0)]);
    far.tick = 10;
    player(&mut far, TARGET).vz = crate::movement::TOP_SPEED;
    assert_eq!(
        sense_of(&mut Interest::default(), &mut far, READER, TARGET, &solids),
        Sense::Hidden
    );
    // Gunfire carries further than feet.
    player(&mut far, TARGET).vz = 0.0;
    player(&mut far, TARGET).just_fired = true;
    assert!(matches!(
        sense_of(&mut Interest::default(), &mut far, READER, TARGET, &solids),
        Sense::Heard(_)
    ));
}

#[test]
fn team_mates_are_always_seen_and_a_downed_reader_rides_their_eyes() {
    let solids = wall();
    // Reader and mate west of the wall at its two ends; the enemy east.
    let mut state = state_with(&[(-5.0, 0.0), (5.0, 0.0), (-4.0, 16.0), (5.0, -5.0)]);
    state.config.rules = crate::rules::RuleSet::new(GameMode::Tdm, &[], false).unwrap();
    for (n, team) in [
        (1, Team::Union),
        (2, Team::Coalition),
        (3, Team::Union),
        (4, Team::Union),
    ] {
        player(&mut state, n).team = Some(team);
    }
    let mut interest = Interest::default();
    state.tick = 20;
    // A mate behind the wall (4) is seen; the enemy behind it (2) is not.
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, 4, &solids),
        Sense::Seen
    );
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Hidden
    );
    // Move the enemy where only the mate at the north end sees it.
    player(&mut state, TARGET).z = 18.0;
    player(&mut state, READER).z = -15.0;
    state.tick = 40;
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Hidden
    );
    // Down, the reader sees what its living mates see.
    player(&mut state, READER).hp = 0;
    state.tick = 41;
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Seen
    );
}

#[test]
fn a_downed_reader_keeps_its_killer_until_it_is_back_up() {
    let solids = wall();
    let mut state = state_with(&[(-5.0, 0.0), (5.0, 0.0)]);
    let mut interest = Interest::default();
    state.tick = 30;
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Hidden
    );
    player(&mut state, READER).hp = 0;
    interest.observe([&ServerMessage::Event(GameEvent::Frag {
        killer: "Probe 2".into(),
        victim: "Probe 1".into(),
        killer_score: 1,
        killer_id: Some(id(TARGET)),
        victim_id: Some(id(READER)),
        weapon: None,
        killer_team: None,
        victim_team: None,
    })]);
    state.tick = 31;
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Seen
    );
    state.tick = 200;
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Seen
    );
    player(&mut state, READER).hp = 100;
    state.tick = 201;
    assert_eq!(
        sense_of(&mut interest, &mut state, READER, TARGET, &solids),
        Sense::Hidden
    );
}

#[test]
fn outside_a_live_round_every_reader_sees_everybody() {
    let solids = wall();
    let mut state = state_with(&[(-5.0, 0.0), (5.0, 0.0)]);
    state.round_state = RoundState::Ended;
    let snapshot = state.snapshot();
    assert!(Interest::default()
        .views_in(&state, &snapshot, &[id(READER)], &solids)
        .is_empty());
}

#[test]
fn views_cut_the_world_text_and_share_identical_views() {
    let solids = wall();
    // Readers 1 and 3 both stand west of the wall; 2 is east of it.
    let mut state = state_with(&[(-5.0, 0.0), (5.0, 0.0), (-6.0, -2.0)]);
    let mut interest = Interest::default();
    let snapshot = state.snapshot();
    // Every pair traces within two ticks.
    state.tick = 7;
    interest.views_in(&state, &snapshot, &[id(1), id(2), id(3)], &solids);
    state.tick = 8;
    let views = interest.views_in(&state, &snapshot, &[id(1), id(2), id(3)], &solids);
    let world = Broadcast::encode(ServerMessage::Snapshot(snapshot.clone())).unwrap();
    let cut = encode_views(&world, &views).unwrap();
    // 1 and 3 see each other and not 2; 2 sees neither. 1 and 3 each hide
    // only 2, so they share one text.
    assert!(Arc::ptr_eq(&cut[&id(1)], &cut[&id(3)]));
    for reader in [1, 2] {
        let view = &cut[&id(reader)];
        assert!(view.is_view());
        let parsed: serde_json::Value = serde_json::from_str(view.text()).unwrap();
        let rows = parsed["players"].as_array().unwrap();
        assert_eq!(rows.len(), 3, "the roster keeps every fighter");
        for row in rows {
            let other = row["id"] != serde_json::json!(id(reader).to_string());
            let hidden =
                other && (reader == 2 || row["id"] == serde_json::json!(id(2).to_string()));
            assert_eq!(row.get("sense").is_some(), hidden, "{row}");
            if hidden {
                assert_eq!(row["sense"], "hidden");
                assert_eq!(row["hp"], 0);
            }
        }
        // Everything outside the roster is the world's own text.
        let mut whole: serde_json::Value = serde_json::from_str(world.text()).unwrap();
        let mut mine = parsed.clone();
        whole.as_object_mut().unwrap().remove("players");
        mine.as_object_mut().unwrap().remove("players");
        assert_eq!(whole, mine);
        // A view parses back to the message the reader receives.
        let ServerMessage::Snapshot(sent) = view.sent_message() else {
            panic!("a view is a world");
        };
        assert!(sent
            .players
            .iter()
            .any(|row| row.sense == Some(PlayerSense::Hidden)));
    }
    // With nothing withheld no view is cut: the reader shares the world.
    let mut open_interest = Interest::default();
    open_interest.views_in(&state, &snapshot, &[id(1)], &[]);
    state.tick = 9;
    let open = open_interest.views_in(&state, &snapshot, &[id(1)], &[]);
    assert!(encode_views(&world, &open).unwrap().is_empty());
}

/// Stand `reader` and the other fighter where the session's own walls hide
/// the other from the reader. False when the map hides no such pair.
fn hide_from(state: &mut GameState, reader: Uuid) -> bool {
    let spots: Vec<[f32; 2]> = crate::maps::spawn_table(crate::sim::MapKind::ArenaDuel)
        .expect("Larak Lot has a spawn table")
        .iter()
        .map(|spawn| [spawn[0], spawn[2]])
        .collect();
    for a in &spots {
        for b in &spots {
            for player in state.players.iter_mut() {
                let at = if player.id == reader { a } else { b };
                player.x = at[0];
                player.z = at[1];
                player.vx = 0.0;
                player.vz = 0.0;
            }
            let snapshot = state.snapshot();
            let mut probe = Interest::default();
            let views = probe.views(state, &snapshot, &[reader]);
            if views.get(&reader).is_some_and(|view| !view.rows.is_empty()) {
                return true;
            }
        }
    }
    false
}

#[tokio::test]
async fn a_fighter_socket_gets_its_view_while_a_spectator_gets_the_world() {
    use crate::net::{ClientSession, GameCommand};
    let (fighter, rival, watcher) = (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    let mut session = crate::session::GameSession::new();
    session.state.config.rules = crate::rules::RuleSet::arsenal();
    for (client, name) in [(fighter, "Reader"), (rival, "Rival")] {
        session.apply_command(GameCommand::Connected {
            body: crate::protocol::BodyKind::Human,
            id: client,
            role: Role::Human,
            name: name.into(),
            player_id: Some(Uuid::new_v4()),
        });
    }
    session.apply_command(GameCommand::Connected {
        body: crate::protocol::BodyKind::Human,
        id: watcher,
        role: Role::Spectator,
        name: "Booth".into(),
        player_id: None,
    });
    session.state.start_round();
    session.state.round_state = RoundState::Active;
    session.state.spawn_shields.clear();
    for player in session.state.players.iter_mut() {
        player.respawn_timer = None;
        player.hp = 100;
    }
    let reader_player = session.client_to_player[&fighter];
    assert!(
        hide_from(&mut session.state, reader_player),
        "the map hides some pair"
    );
    let hidden_id = session.client_to_player[&rival];
    let messages = vec![ServerMessage::Snapshot(session.state.snapshot())];
    let broadcasts = Broadcast::encode_all(messages).unwrap();
    let views = session.interest_views(&broadcasts).unwrap();
    assert!(!views.contains_key(&watcher), "a spectator keeps the world");
    let (fighter_tx, mut fighter_rx) = crate::net::outbound_channel(8);
    let (watcher_tx, mut watcher_rx) = crate::net::outbound_channel(8);
    let clients = Arc::new(tokio::sync::Mutex::new(vec![
        ClientSession::new(fighter, fighter_tx, crate::protocol::GAMEPLAY_VERSION),
        ClientSession::new(watcher, watcher_tx, crate::protocol::GAMEPLAY_VERSION),
    ]));
    for client in clients.lock().await.iter_mut() {
        client.initialized = true;
    }
    crate::session::broadcast_views_to_clients(
        &clients,
        &broadcasts,
        &session.spectator_ids(),
        &views,
    )
    .await;
    let row_of = |message: ServerMessage, id: Uuid| match message {
        ServerMessage::Snapshot(snapshot) => snapshot
            .players
            .into_iter()
            .find(|row| row.id == id)
            .unwrap(),
        other => panic!("expected a world, got {other:?}"),
    };
    let watched = row_of(watcher_rx.try_recv().unwrap(), hidden_id);
    assert_eq!(watched.sense, None);
    assert!(watched.hp > 0);
    assert!(views.contains_key(&fighter));
    let felt = row_of(fighter_rx.try_recv().unwrap(), hidden_id);
    assert!(views[&fighter].muted.is_empty(), "a world mutes nothing");
    assert!(felt.sense.is_some(), "the reader does not see its rival");
    assert_eq!(felt.hp, 0);
}

#[test]
fn a_moving_reader_sees_over_the_step_it_is_about_to_climb() {
    // A wall chest high on a standing fighter, with the target crouched
    // behind it: only an eye a step higher clears it.
    let solids = vec![Solid::from_center_top(0.0, 0.0, 0.5, 6.0, 1.75)];
    let mut state = state_with(&[(-4.0, 0.0), (6.0, 0.0)]);
    player(&mut state, TARGET).ducking = true;
    let mut still = Interest::default();
    assert_eq!(
        sense_of(&mut still, &mut state, READER, TARGET, &solids),
        Sense::Hidden
    );
    player(&mut state, READER).vz = crate::movement::TOP_SPEED;
    let mut moving = Interest::default();
    assert_eq!(
        sense_of(&mut moving, &mut state, READER, TARGET, &solids),
        Sense::Seen
    );
}

#[test]
fn a_seated_reader_leads_on_the_motion_of_its_seat() {
    // No walking velocity, as in a vehicle seat: the measured motion still
    // carries the eye past the corner.
    let solids = wall();
    let mut state = state_with(&[(-3.0, 8.0), (3.0, 0.0)]);
    let mut interest = Interest::default();
    let mut sent = None;
    for step in 0..40_u64 {
        state.tick = 100 + step;
        player(&mut state, READER).z = 8.0 + step as f32 * 0.5;
        if sense_once(&mut interest, &state, READER, TARGET, &solids) == Sense::Seen {
            sent = Some(step);
            break;
        }
    }
    let mut truth = None;
    for step in 0..40_u64 {
        player(&mut state, READER).z = 8.0 + step as f32 * 0.5;
        if truly_visible(&state, READER, TARGET, &solids) {
            truth = Some(step);
            break;
        }
    }
    assert!(
        sent.unwrap() + 3 <= truth.unwrap(),
        "sent {sent:?}, visible {truth:?}"
    );
}

/// Views of `snapshot` after two ticks of tracing, the tick before and this.
fn views_twice(
    interest: &mut Interest,
    state: &mut GameState,
    snapshot: &Snapshot,
    readers: &[Uuid],
    solids: &[Solid],
) -> HashMap<Uuid, View> {
    let tick = state.tick;
    state.tick = tick - 1;
    interest.views_in(state, snapshot, readers, solids);
    state.tick = tick;
    interest.views_in(state, snapshot, readers, solids)
}

fn shot(shooter: u128, target: Option<u128>, at: [f32; 3]) -> ShotResult {
    ShotResult {
        sense: None,
        shooter_id: id(shooter),
        shooter: format!("Probe {shooter}"),
        hit: target.is_some(),
        target_id: target.map(id),
        target: target.map(|n| format!("Probe {n}")),
        damage: if target.is_some() { 12 } else { 0 },
        target_hp_after: target.map(|_| 88),
        trace: Some(ShotTrace {
            vehicle_id: None,
            weapon: crate::protocol::WeaponType::Scatter,
            origin: at,
            end: [at[0] - 6.0, at[1], at[2]],
            impact: ShotImpact::Solid {
                normal: [1.0, 0.0, 0.0],
            },
            pellets: vec![crate::protocol::PelletTrace {
                end: [at[0] - 6.0, at[1], at[2] + 0.4],
                impact: ShotImpact::Range,
            }],
        }),
        killed: false,
        zone: None,
    }
}

fn parsed_world(broadcast: &Broadcast) -> Snapshot {
    match broadcast.sent_message() {
        ServerMessage::Snapshot(snapshot) => snapshot,
        other => panic!("a world, got {other:?}"),
    }
}

#[test]
fn shots_follow_the_senses_of_their_shooter() {
    // The reader (1) west of the wall; 2 behind it and near enough to be
    // heard firing; 3 behind it and too far to hear; 4 in the open.
    let solids = wall();
    let mut state = state_with(&[(-5.0, 0.0), (5.0, 0.0), (45.0, 0.0), (-5.0, 12.0)]);
    player(&mut state, 2).just_fired = true;
    player(&mut state, 3).just_fired = true;
    let mut snapshot = state.snapshot();
    snapshot.shot_results = vec![
        shot(1, None, [-5.0, 1.6, 0.0]),
        shot(2, None, [5.0, 1.6, 0.0]),
        shot(3, None, [45.0, 1.6, 0.0]),
        shot(4, Some(2), [-5.0, 1.6, 12.0]),
        shot(3, Some(1), [45.0, 1.6, 0.0]),
    ];
    let mut interest = Interest::default();
    let views = views_twice(&mut interest, &mut state, &snapshot, &[id(1)], &solids);
    let view = &views[&id(1)];
    assert!(
        matches!(
            view.shots.as_slice(),
            [(1, Sense::Heard(_)), (2, Sense::Hidden)]
        ),
        "{view:?}"
    );
    let world = Broadcast::encode(ServerMessage::Snapshot(snapshot.clone())).unwrap();
    let cut = encode_views(&world, &views).unwrap();
    let sent = parsed_world(&cut[&id(1)]);
    // Its own shot, the open fighter's and the one that struck it are whole;
    // the far one's other shot is gone; the heard one is cut.
    assert_eq!(sent.shot_results.len(), 4);
    assert_eq!(sent.shot_results[0], snapshot.shot_results[0]);
    assert_eq!(sent.shot_results[2], snapshot.shot_results[3]);
    assert_eq!(
        sent.shot_results[3], snapshot.shot_results[4],
        "a shot that strikes the reader stays whole"
    );
    let heard = &sent.shot_results[1];
    let Sense::Heard(at) = view.shots[0].1 else {
        unreachable!()
    };
    assert_eq!(heard.sense, Some(PlayerSense::Heard));
    assert_eq!(
        (heard.shooter_id, heard.hit, heard.damage),
        (id(2), false, 0)
    );
    let trace = heard.trace.as_ref().expect("the gun stays");
    assert_eq!(trace.weapon, crate::protocol::WeaponType::Scatter);
    assert_eq!(trace.impact, ShotImpact::Range);
    assert!(trace.pellets.is_empty(), "no pellets to trace back");
    let rounded = |v: [f32; 3]| v.map(|c| (c * 1000.0).round() / 1000.0);
    assert_eq!(rounded(trace.origin), rounded(at));
    assert_eq!(trace.origin, trace.end);
    // The place is the heard row's own: the shot says no more than the row.
    let row = sent.players.iter().find(|row| row.id == id(2)).unwrap();
    assert_eq!(row.sense, Some(PlayerSense::Heard));
    assert!((row.x - trace.origin[0]).abs() < 0.01 && (row.z - trace.origin[2]).abs() < 0.01);
    // Everything else is the world's own text.
    let mut whole: serde_json::Value = serde_json::from_str(world.text()).unwrap();
    let mut mine: serde_json::Value = serde_json::from_str(cut[&id(1)].text()).unwrap();
    for value in [&mut whole, &mut mine] {
        let object = value.as_object_mut().unwrap();
        object.remove("players");
        object.remove("shot_results");
    }
    assert_eq!(whole, mine);
    // A fighter that is not a reader (a spectator's socket) gets no view.
    assert!(!views.contains_key(&id(4)));
}

#[test]
fn a_throw_from_an_unseen_fighter_is_sent_only_once_a_line_reaches_it() {
    use crate::protocol::{MinePhase, MineState, RocketState};
    let solids = wall();
    // 2 throws from behind the wall, far enough to stay unheard.
    let mut state = state_with(&[(-5.0, 0.0), (40.0, 0.0)]);
    let rocket = |n: u32, at: [f32; 3]| RocketState {
        id: n,
        owner_id: id(2),
        position: at,
        velocity: [0.0, 0.0, 0.0],
        age_ticks: 3,
    };
    let mine = |n: u32, phase: MinePhase| MineState {
        id: n,
        owner_id: id(2),
        position: [30.0, 1.0, 0.0],
        normal: [0.0, 1.0, 0.0],
        phase,
        phase_started: 1,
        phase_ends: 1,
    };
    let mut snapshot = state.snapshot();
    snapshot.rockets = vec![rocket(1, [30.0, 1.5, 0.0]), rocket(2, [-3.0, 1.5, 14.0])];
    snapshot.mines = vec![mine(3, MinePhase::Flying), mine(4, MinePhase::Armed)];
    let mut interest = Interest::default();
    let views = views_twice(&mut interest, &mut state, &snapshot, &[id(1)], &solids);
    let view = &views[&id(1)];
    assert_eq!(view.rows.len(), 1, "{view:?}");
    // The rocket behind the wall and the mine in flight there are left out;
    // the rocket round the corner and the stuck mine are sent.
    assert_eq!(view.things, vec![(Thing::Rocket, 0), (Thing::Mine, 0)]);
    let world = Broadcast::encode(ServerMessage::Snapshot(snapshot.clone())).unwrap();
    let sent = parsed_world(&encode_views(&world, &views).unwrap()[&id(1)]);
    assert_eq!(sent.rockets, vec![snapshot.rockets[1].clone()]);
    assert_eq!(sent.mines, vec![snapshot.mines[1].clone()]);
    // Once it flies into the open it is sent, and stays a grace after.
    snapshot.rockets[0].position = [-3.0, 1.5, 14.0];
    state.tick += 1;
    let views = interest.views_in(&state, &snapshot, &[id(1)], &solids);
    assert!(!views[&id(1)].things.contains(&(Thing::Rocket, 0)));
    snapshot.rockets[0].position = [30.0, 1.5, 0.0];
    state.tick += 1;
    let views = interest.views_in(&state, &snapshot, &[id(1)], &solids);
    assert!(
        !views[&id(1)].things.contains(&(Thing::Rocket, 0)),
        "kept the grace"
    );
    state.tick += SEEN_GRACE + 1;
    let views = interest.views_in(&state, &snapshot, &[id(1)], &solids);
    assert!(views[&id(1)].things.contains(&(Thing::Rocket, 0)));
    // In the open, the thrower is seen and so is everything it throws.
    let mut open = Interest::default();
    let views = views_twice(&mut open, &mut state, &snapshot, &[id(1)], &[]);
    assert!(views[&id(1)].is_empty());
}

#[test]
fn a_pickup_by_an_unseen_fighter_is_muted_except_the_plate() {
    let solids = wall();
    let mut state = state_with(&[(-5.0, 0.0), (40.0, 0.0)]);
    let snapshot = state.snapshot();
    let mut interest = Interest::default();
    let views = views_twice(&mut interest, &mut state, &snapshot, &[id(1)], &solids);
    let view = &views[&id(1)];
    let pickup = |n: u128, kind: &str| {
        ServerMessage::Event(GameEvent::Pickup {
            player: format!("Probe {n}"),
            player_id: id(n),
            kind: kind.into(),
            weapon: String::new(),
            amount: Some(25),
            pickup_id: format!("{kind}_pad"),
            secret: false,
        })
    };
    assert!(view.mutes(&snapshot, &pickup(2, "armor")));
    assert!(
        !view.mutes(&snapshot, &pickup(2, "plate")),
        "the venue answers the Plate"
    );
    assert!(
        !view.mutes(&snapshot, &pickup(1, "armor")),
        "the reader's own pickup"
    );
    let frag = ServerMessage::Event(GameEvent::Frag {
        killer: "Probe 2".into(),
        victim: "Probe 3".into(),
        killer_score: 1,
        killer_id: Some(id(2)),
        victim_id: Some(id(3)),
        weapon: None,
        killer_team: None,
        victim_team: None,
    });
    assert!(
        !view.mutes(&snapshot, &frag),
        "the kill feed is for everyone"
    );
}

#[test]
fn the_session_mutes_an_unseen_pickup_on_a_fighter_socket_only() {
    use crate::net::GameCommand;
    let (fighter, rival) = (Uuid::new_v4(), Uuid::new_v4());
    let mut session = crate::session::GameSession::new();
    session.state.config.rules = crate::rules::RuleSet::arsenal();
    for (client, name) in [(fighter, "Reader"), (rival, "Rival")] {
        session.apply_command(GameCommand::Connected {
            body: crate::protocol::BodyKind::Human,
            id: client,
            role: Role::Human,
            name: name.into(),
            player_id: Some(Uuid::new_v4()),
        });
    }
    session.state.start_round();
    session.state.round_state = RoundState::Active;
    session.state.spawn_shields.clear();
    for player in session.state.players.iter_mut() {
        player.respawn_timer = None;
        player.hp = 100;
    }
    let reader = session.client_to_player[&fighter];
    assert!(
        hide_from(&mut session.state, reader),
        "the map hides some pair"
    );
    let hidden = session.client_to_player[&rival];
    let messages = vec![
        ServerMessage::Event(GameEvent::Pickup {
            player: "Rival".into(),
            player_id: hidden,
            kind: "health".into(),
            weapon: String::new(),
            amount: Some(40),
            pickup_id: "health_pad".into(),
            secret: false,
        }),
        ServerMessage::Snapshot(session.state.snapshot()),
    ];
    let broadcasts = Broadcast::encode_all(messages).unwrap();
    let views = session.interest_views(&broadcasts).unwrap();
    assert_eq!(views[&fighter].muted, vec![0]);
    // The rival may see the reader or not; either way it hears its own pickup.
    assert!(views.get(&rival).is_none_or(|cut| cut.muted.is_empty()));
}
