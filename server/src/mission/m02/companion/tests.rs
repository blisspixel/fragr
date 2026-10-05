use super::*;
use crate::maps::AuthoredSource;
use crate::movement::{Arena, Solid};
use crate::navigation::Navigation;
use crate::protocol::{MissionReady, Role};
use crate::session::GameSession;

fn place(state: &mut GameState, id: Uuid, feet: [f32; 3]) {
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [player.x, player.y, player.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    player.vy = 0.0;
    player.clear_input();
}

fn recorded_roof() -> (GameSession, Uuid, Uuid) {
    let mut session = GameSession::with_authored_map(
        AuthoredSource::Mission(MissionId::ScheduledService)
            .load()
            .unwrap(),
    );
    session.state.use_replay_ids();
    session.state.seed(42);
    let id = Uuid::from_u128(0xec14);
    session.state.add_player(id, "Walker".into(), Role::Human);
    assert!(session.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::ScheduledService,
            attempt: 1,
        }
    ));
    session.tick_messages(0.05);
    let companion = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .unwrap()
        .id;
    for player in session
        .state
        .players
        .iter_mut()
        .filter(|p| p.is_campaign_enemy())
    {
        player.hp = 0;
    }
    let geometry = session.state.map.m03_geometry().unwrap();
    for (car, authored) in session
        .state
        .mission
        .as_mut()
        .unwrap()
        .m03
        .as_mut()
        .unwrap()
        .cars
        .iter_mut()
        .zip(geometry.cars)
    {
        car.released = true;
        car.captives = authored.safe;
    }
    place(&mut session.state, id, [-15.937356, 0.0, 8.173295]);
    place(&mut session.state, companion, [-15.009286, 0.0, 7.7506742]);
    (session, id, companion)
}

fn toward(state: &GameState, id: Uuid, goal: [f32; 2]) -> Action {
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    Action {
        forward: true,
        yaw: Some((goal[1] - player.z).atan2(goal[0] - player.x)),
        ..Default::default()
    }
}

#[test]
fn companion_recorded_roof_wedge_opens_with_real_session_walking() {
    // Reproduce the old close-follow collision with real GameState integration,
    // then compare the same supported world and all civilian bodies in Session.
    let (mut old, id, companion) = recorded_roof();
    let start = old
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .map(|p| [p.x, p.z])
        .unwrap();
    for _ in 0..40 {
        old.state
            .set_action(id, toward(&old.state, id, [-16.5, 18.0]));
        let leader = old.state.players.iter().find(|p| p.id == id).unwrap();
        let follow = toward(&old.state, companion, [leader.x, leader.z]);
        old.state.set_companion_action(companion, follow);
        old.state.tick(0.05);
    }
    let stuck = old.state.players.iter().find(|p| p.id == id).unwrap();
    assert!(
        (stuck.x - start[0]).hypot(stuck.z - start[1]) < 0.01,
        "old direct follow must reproduce contact wedge: {:?}",
        [stuck.x, stuck.z]
    );

    for _repeat in 0..2 {
        let (mut live, id, companion) = recorded_roof();
        let mut arrived = false;
        for _ in 0..100 {
            live.state
                .set_action(id, toward(&live.state, id, [-16.5, 18.0]));
            live.tick_messages(0.05);
            let walker = live.state.players.iter().find(|p| p.id == id).unwrap();
            let ally = live
                .state
                .players
                .iter()
                .find(|p| p.id == companion)
                .unwrap();
            assert_eq!(walker.hp, 100);
            assert_eq!(walker.y, PLAYER_FLOOR_Y);
            assert_eq!(ally.y, PLAYER_FLOOR_Y);
            assert!((walker.x - ally.x).hypot(walker.z - ally.z) >= 0.9999);
            assert_eq!(
                live.state.mission_state().unwrap().m03.unwrap().cars[2].captives,
                [[-16.5, 0.0, 7.0], [-16.5, 0.0, 9.0]]
            );
            if (walker.x + 16.5).hypot(walker.z - 18.0) < 0.3 {
                arrived = true;
                break;
            }
        }
        assert!(
            arrived,
            "normal original northbound goal must arrive with all bodies retained: {:?}",
            live.state
                .players
                .iter()
                .map(|p| (&p.name, [p.x, p.y, p.z]))
                .collect::<Vec<_>>()
        );
    }
}

fn local_scene(feet: [f32; 3], leader: [f32; 3]) -> (GameState, Uuid, Uuid) {
    let mut state = GameState::new();
    let id = Uuid::from_u128(1);
    state.add_player(id, "Walker".into(), Role::Human);
    let ally = state.spawn_campaign_companion(feet, false).unwrap();
    place(&mut state, id, leader);
    (state, id, ally)
}

#[test]
fn companion_local_yield_respects_support_corners_and_no_retreat() {
    let (state, _, ally) = local_scene([1.1, 3.0, 0.0], [0.0, 3.0, 0.0]);
    let me = state.players.iter().find(|p| p.id == ally).unwrap();
    let bodies = state.contact_bodies();
    let deck = Solid {
        min_x: -3.0,
        max_x: 2.0,
        min_z: -2.0,
        max_z: 2.0,
        bottom: 0.0,
        top: 3.0,
    };
    let arena = Arena {
        half: 10.0,
        solids: vec![deck],
    };
    let goal = formation::goal(&arena, me, [0.0, 3.0, 0.0], false, &bodies).unwrap();
    assert_eq!(goal.feet[1], 3.0);
    assert!(
        goal.feet[2].abs() > 0.6 && goal.feet[0] < 2.0,
        "unsupported outward retreat must turn onto supported deck: {goal:?}"
    );
    let confined = Arena {
        half: 10.0,
        solids: vec![
            Solid {
                min_x: -2.0,
                max_x: 2.0,
                min_z: -2.0,
                max_z: 2.0,
                bottom: 0.0,
                top: 3.0,
            },
            Solid {
                min_x: 1.6,
                max_x: 2.0,
                min_z: -2.0,
                max_z: 2.0,
                bottom: 3.0,
                top: 6.0,
            },
            Solid {
                min_x: -2.0,
                max_x: 2.0,
                min_z: 0.6,
                max_z: 2.0,
                bottom: 3.0,
                top: 6.0,
            },
            Solid {
                min_x: -2.0,
                max_x: 2.0,
                min_z: -2.0,
                max_z: -0.6,
                bottom: 3.0,
                top: 6.0,
            },
        ],
    };
    assert!(formation::goal(&confined, me, [0.0, 3.0, 0.0], false, &bodies).is_none());
}

#[test]
fn companion_stand_off_is_deterministic_clear_and_holds_formation() {
    let arena = Arena {
        half: 12.0,
        solids: vec![],
    };
    let (mut state, id, ally) = local_scene([7.0, 0.0, 0.0], [0.0, 0.0, 0.0]);
    let me = state.players.iter().find(|p| p.id == ally).unwrap();
    let bodies = state.contact_bodies();
    let first = formation::goal(&arena, me, [0.0, 0.0, 0.0], false, &bodies).unwrap();
    for _ in 0..100 {
        assert_eq!(
            formation::goal(&arena, me, [0.0, 0.0, 0.0], false, &bodies)
                .unwrap()
                .feet,
            first.feet
        );
    }
    assert!((first.feet[0].hypot(first.feet[2]) - 2.4).abs() < 0.001);
    assert!(Navigation::walkable_in(
        &arena,
        [me.x, 0.0, me.z],
        first.feet
    ));
    assert_eq!(
        formation::goal(&arena, me, [0.0, 0.0, 0.0], true, &bodies)
            .unwrap()
            .feet,
        [-2.4, 0.0, 1.2],
        "M02 retains the exact authored west-forward slot"
    );
    place(&mut state, ally, [2.4, 0.0, 0.0]);
    let me = state.players.iter().find(|p| p.id == ally).unwrap();
    assert!(formation::goal(&arena, me, [0.0, 0.0, 0.0], false, &state.contact_bodies()).is_none());
    assert!(state.players.iter().any(|p| p.id == id && p.hp == 100));
}

#[test]
fn companion_idle_release_and_mission_phase_drop_stale_goal() {
    let (mut session, id, ally) = recorded_roof();
    assert!(session
        .state
        .m02_companion_intent()
        .unwrap()
        .1
        .goal
        .is_some());
    place(&mut session.state, ally, [-13.5, 0.0, 8.173295]);
    let hold = session.state.m02_companion_intent().unwrap().1;
    assert!(hold.goal.is_none() && !hold.action.forward && !hold.action.fire);
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .hp = 0;
    assert!(session
        .state
        .m02_companion_intent()
        .unwrap()
        .1
        .goal
        .is_none());
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .hp = 100;
    session.state.mission.as_mut().unwrap().phase = MissionPhase::Briefing;
    assert!(session.state.m02_companion_intent().is_none());
    session.state.mission.as_mut().unwrap().phase = MissionPhase::InProgress;
    let player = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == ally)
        .unwrap();
    if let Some(CampaignActor::Companion { phase, .. }) = player.campaign.as_mut() {
        *phase = CompanionPhase::Releasing;
    }
    assert!(session.state.m02_companion_intent().is_none());
}
