use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, Role};

fn state() -> GameState {
    GameState::with_authored_map(
        AuthoredMap::read(
            serde_json::to_vec(&super::tests::definition())
                .unwrap()
                .as_slice(),
        )
        .unwrap(),
    )
}

fn join(state: &mut GameState) -> Uuid {
    let id = Uuid::new_v4();
    state.add_player(id, "Reader".into(), Role::Human);
    id
}

fn ready(state: &mut GameState, id: Uuid) -> bool {
    let mission = state.mission_state().unwrap();
    state.acknowledge_mission(
        id,
        MissionReady {
            id: mission.id,
            attempt: mission.attempt,
        },
    )
}

#[test]
fn initial_party_waits_for_every_reader_and_discards_early_input() {
    let mut state = state();
    let first = join(&mut state);
    let second = join(&mut state);
    let initial = state.snapshot();
    assert_eq!(state.mission_state().unwrap().phase, MissionPhase::Briefing);
    for _ in 0..20 {
        state.set_action(
            first,
            Action {
                forward: true,
                jump: true,
                fire: true,
                interact: true,
                ..Action::default()
            },
        );
        state.tick(0.05);
    }
    assert!(ready(&mut state, first));
    state.tick(0.05);
    assert_eq!(state.mission_state().unwrap().phase, MissionPhase::Briefing);
    assert!(state.mission_state().unwrap().prompts.is_empty());
    for (before, after) in initial.players.iter().zip(&state.snapshot().players) {
        assert_eq!(
            (before.x, before.y, before.z, before.hp),
            (after.x, after.y, after.z, after.hp)
        );
    }
    assert!(state.players.iter().all(|p| !p.just_fired));
    assert!(ready(&mut state, second));
    assert_eq!(
        state.mission_state().unwrap().phase,
        MissionPhase::FindTransfer
    );
    let position = (state.players[0].x, state.players[0].y, state.players[0].z);
    state.tick(0.05);
    assert_eq!(
        (state.players[0].x, state.players[0].y, state.players[0].z),
        position
    );
    assert!(!state.players[0].just_fired);
    state.set_action(
        first,
        Action {
            forward: true,
            ..Action::default()
        },
    );
    assert!(
        !ready(&mut state, first),
        "duplicate readiness cannot clear active input"
    );
    state.tick(0.05);
    assert_ne!(
        (state.players[0].x, state.players[0].y, state.players[0].z),
        position
    );
}

#[test]
fn an_unread_departure_removes_the_initial_wait() {
    let mut state = state();
    let first = join(&mut state);
    let second = join(&mut state);
    assert!(ready(&mut state, first));
    state.remove_player(second);
    let mission = state.mission_state().unwrap();
    assert_eq!(mission.phase, MissionPhase::FindTransfer);
    assert_eq!(mission.party.len(), 1);
    assert!(mission.party[0].ready);
    assert_eq!(state.mission.as_ref().unwrap().ready.len(), 1);
}

#[test]
fn late_readers_cannot_pause_or_keep_a_defeated_party_alive() {
    let mut state = state();
    let active = join(&mut state);
    assert!(ready(&mut state, active));
    let reader = join(&mut state);
    assert_eq!(
        state.mission_state().unwrap().phase,
        MissionPhase::FindTransfer
    );
    state.set_action(
        active,
        Action {
            forward: true,
            ..Action::default()
        },
    );
    let before = state.players[0].z;
    state.tick(0.05);
    assert_ne!(state.players[0].z, before);
    state.players[0].hp = 0;
    state.players[0].respawn_timer = Some(2);
    state.tick(0.05);
    let mission = state.mission_state().unwrap();
    assert_eq!(
        mission.attempt, 2,
        "a late reader cannot prevent the party reset"
    );
    assert!(mission.party.iter().find(|p| p.id == active).unwrap().ready);
    assert!(!mission.party.iter().find(|p| p.id == reader).unwrap().ready);
    assert!(!state.acknowledge_mission(
        reader,
        MissionReady {
            id: mission.id,
            attempt: 1
        }
    ));
    state.tick(0.05);
    assert!(state.players[0].hp > 0);
    assert!(ready(&mut state, reader));
    assert_eq!(state.mission_state().unwrap().attempt, 2);
}

#[test]
fn invalid_identity_revision_and_departed_acknowledgements_do_nothing() {
    let mut state = state();
    let id = join(&mut state);
    let mission = state.mission_state().unwrap();
    assert!(
        !ready(&mut state, Uuid::new_v4()),
        "spectators have no participant identity"
    );
    for attempt in [0, 2, u32::MAX] {
        assert!(!state.acknowledge_mission(
            id,
            MissionReady {
                id: mission.id,
                attempt
            }
        ));
    }
    assert_eq!(state.mission_state().unwrap(), mission);
    state.mission.as_mut().unwrap().phase = MissionPhase::Departed;
    assert!(!ready(&mut state, id));
    assert!(!state.mission_state().unwrap().party[0].ready);
}

#[test]
fn a_pending_reader_cannot_trigger_loot_or_become_an_enemy_target() {
    let mut definition = super::tests::definition();
    definition["encounters"] = serde_json::json!([{
        "id":"intake", "regions":[{"min":[-1,0,-5],"max":[1,2,-3]}],
        "enemies":[{"id":"clerk","kind":"clerk","feet":[0,0,-1.5],"yaw":4.712389}]
    }]);
    let mut session = crate::session::GameSession::with_authored_map(
        AuthoredMap::read(serde_json::to_vec(&definition).unwrap().as_slice()).unwrap(),
    );
    session.state.seed(67);
    let active = join(&mut session.state);
    assert!(ready(&mut session.state, active));
    let reader = join(&mut session.state);
    let reader_index = session
        .state
        .players
        .iter()
        .position(|p| p.id == reader)
        .unwrap();
    session.state.players[reader_index].z = -4.0;
    session.state.players[reader_index].hp = 50;
    session.state.pickups.push(crate::sim::ArenaPickup {
        id: "reader_health".into(),
        kind: crate::sim::PickupKind::Health,
        amount: 25,
        claim: crate::protocol::SupplyClaim::Contested,
        x: 0.0,
        y: 0.1,
        z: -4.0,
        floor: 0.0,
        available: true,
        respawn_timer: None,
    });
    for _ in 0..20 {
        session.tick_messages(0.05);
    }
    assert_eq!(
        session.state.players.len(),
        2,
        "a reader cannot activate the encounter"
    );
    assert!(session.state.pickups[0].available);
    assert_eq!(session.state.players[reader_index].hp, 50);

    session.state.players[0].z = -4.0;
    session.tick_messages(0.05);
    assert_eq!(session.state.players.len(), 3);
    // The active participant is now hidden behind the closed gate. The reader
    // is the only visible body; it must not attract the guard's attack.
    session.state.players[0].z = 3.0;
    for _ in 0..100 {
        session.tick_messages(0.05);
        assert!(session.state.shot_results.is_empty());
    }
    assert_eq!(session.state.players[reader_index].hp, 50);
    assert!(session.state.pickups[0].available);

    let clerk = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap()
        .id;
    session.state.set_action(
        clerk,
        Action {
            fire: true,
            look_at: Some(crate::protocol::LookAt {
                x: Some(0.0),
                y: Some(crate::combat::FIGHTER_HEIGHT * 0.5),
                z: Some(-4.0),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    session.state.tick(0.05);
    assert_eq!(
        session.state.shot_results.len(),
        1,
        "exercise an actual ray through the reader"
    );
    assert_eq!(session.state.shot_results[0].target_id, None);
    assert_eq!(session.state.players[reader_index].hp, 50);
    session.state.set_action(clerk, Action::default());

    assert!(ready(&mut session.state, reader));
    session.tick_messages(0.05);
    assert!(!session.state.pickups[0].available);
    assert_eq!(session.state.players[reader_index].hp, 75);
    let mut hit = false;
    for _ in 0..100 {
        session.tick_messages(0.05);
        hit |= session
            .state
            .shot_results
            .iter()
            .any(|shot| shot.target_id == Some(reader));
    }
    assert!(
        hit,
        "acknowledgment restores ordinary enemy targeting and damage"
    );
}

#[test]
fn wire_controllers_wait_for_validated_participation_before_acting_or_deciding() {
    let mut state = state();
    let id = join(&mut state);
    let mut observer = MissionClient::default();
    assert!(
        observer.participating(id),
        "arcade behavior stays compatible"
    );
    observer
        .replace_map(
            state.map.mission(),
            state.map.arena().half,
            &state.map.arena().solids,
            state.map.presentation_ref(),
        )
        .unwrap();
    assert!(
        !observer.participating(id),
        "mission map alone is not participation"
    );
    assert!(observer.readiness(Some(id)).is_none());
    observer
        .observe(state.tick, state.mission_state().unwrap())
        .unwrap();
    assert!(!observer.participating(id));
    assert!(observer.readiness(None).is_none());
    assert!(observer.readiness(Some(Uuid::new_v4())).is_none());
    let acknowledgement = observer.readiness(Some(id)).unwrap();
    assert!(state.acknowledge_mission(id, acknowledgement));
    observer
        .observe(state.tick, state.mission_state().unwrap())
        .unwrap();
    assert!(observer.participating(id));
    assert!(observer.readiness(Some(id)).is_none());
    state.mission.as_mut().unwrap().phase = MissionPhase::Departed;
    observer
        .observe(state.tick, state.mission_state().unwrap())
        .unwrap();
    assert!(!observer.participating(id));
    assert!(observer.readiness(Some(id)).is_none());
}
