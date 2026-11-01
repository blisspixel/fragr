use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, CampaignRunStatus, MissionId, MissionReady, Role};
use serde_json::{json, Value};

/// The shared mission fixture, optionally with one dormant guard group whose
/// entry region the test walks into.
fn state_with(definition: Value) -> (GameState, Uuid) {
    let map = AuthoredMap::read(serde_json::to_vec(&definition).unwrap().as_slice()).unwrap();
    let mut state = GameState::with_authored_map(map);
    state.use_replay_ids();
    state.seed(7);
    state.enable_campaign_run().unwrap();
    let id = Uuid::from_u128(77);
    state.add_player(id, "Checkpoint test".into(), Role::Human);
    let player = &mut state.players[0];
    player.inventory.grant_weapon(WeaponType::Tack);
    player.weapon = WeaponType::Tack;
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::RecallNotice,
            attempt: 1,
        },
    ));
    (state, id)
}

fn plain() -> (GameState, Uuid) {
    state_with(super::super::tests::definition())
}

fn guarded() -> (GameState, Uuid) {
    let mut definition = super::super::tests::definition();
    definition["encounters"] = json!([{
        "id": "desk_watch",
        "regions": [{"min": [-6, 0, -5], "max": [6, 2, -1]}],
        "enemies": [{"id": "desk_clerk", "kind": "clerk", "feet": [5, 0, -1.5], "yaw": 3.0}]
    }]);
    state_with(definition)
}

fn idle(state: &mut GameState, ticks: u64) {
    for _ in 0..ticks {
        state.tick(0.05);
    }
}

fn request(state: &GameState) -> MissionContinue {
    let mission = state.mission_state().unwrap();
    MissionContinue {
        id: mission.id,
        run_id: mission.run.unwrap().id,
        attempt: mission.attempt,
    }
}

fn die(state: &mut GameState, id: Uuid) {
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.hp = 0;
    player.respawn_timer = Some(1);
    state.tick(0.05);
    assert_eq!(
        state.mission_state().unwrap().run.unwrap().status,
        CampaignRunStatus::Continue
    );
}

fn checkpoints(state: &GameState) -> Vec<u64> {
    state.campaign_checkpoint_ticks()
}

fn player(state: &GameState, id: Uuid) -> &Player {
    state.players.iter().find(|p| p.id == id).unwrap()
}

#[test]
fn a_quiet_minute_saves_one_checkpoint_and_announces_it() {
    let (mut state, id) = plain();
    let started = state.campaign_attempt_started_at().unwrap();
    while state.tick < started + CHECKPOINT_INTERVAL_TICKS - 1 {
        state.tick(0.05);
    }
    assert!(checkpoints(&state).is_empty(), "no save before the minute");
    state.take_events();
    state.tick(0.05);
    assert_eq!(
        checkpoints(&state),
        vec![started + CHECKPOINT_INTERVAL_TICKS]
    );
    assert!(state
        .take_events()
        .iter()
        .any(|event| matches!(event, GameEvent::Checkpoint {})));
    idle(&mut state, CHECKPOINT_INTERVAL_TICKS - 1);
    assert_eq!(
        checkpoints(&state).len(),
        1,
        "the next waits another minute"
    );
    state.tick(0.05);
    assert_eq!(checkpoints(&state).len(), 2);
    assert!(player(&state, id).hp > 0);
}

#[test]
fn a_due_checkpoint_waits_for_the_ground_and_three_unhurt_seconds() {
    let (mut state, id) = plain();
    let started = state.campaign_attempt_started_at().unwrap();
    while state.tick < started + CHECKPOINT_INTERVAL_TICKS - 2 {
        state.tick(0.05);
    }
    // Hurt just before the minute: the save waits three seconds.
    state.players.iter_mut().find(|p| p.id == id).unwrap().hp -= 10;
    idle(&mut state, CHECKPOINT_HURT_QUIET_TICKS - 2);
    assert!(
        checkpoints(&state).is_empty(),
        "no save while recently hurt"
    );
    // Airborne when the hurt window ends: the save waits for landing.
    state.set_action(
        id,
        Action {
            jump: true,
            ..Default::default()
        },
    );
    let standing = player(&state, id).y;
    state.tick(0.05);
    state.set_action(id, Action::default());
    let mut landed = None;
    for _ in 0..80 {
        let airborne = player(&state, id).y > standing + 0.001;
        if airborne {
            assert!(checkpoints(&state).is_empty(), "no save in the air");
        } else if landed.is_none() {
            landed = Some(state.tick);
        }
        if !checkpoints(&state).is_empty() {
            break;
        }
        state.tick(0.05);
    }
    let landed = landed.expect("the jump lands");
    let saved = checkpoints(&state);
    assert_eq!(saved.len(), 1, "saved once the body is down and unhurt");
    assert!(saved[0] >= landed);
}

#[test]
fn death_spends_a_continue_and_returns_to_the_checkpoint() {
    let (mut state, id) = plain();
    let started = state.campaign_attempt_started_at().unwrap();
    // Walk somewhere, then wait for the minute's checkpoint.
    state.set_action(
        id,
        Action {
            forward: true,
            ..Default::default()
        },
    );
    idle(&mut state, 10);
    state.set_action(id, Action::default());
    while checkpoints(&state).is_empty() {
        state.tick(0.05);
        assert!(state.tick < started + 2 * CHECKPOINT_INTERVAL_TICKS);
    }
    let saved_at = checkpoints(&state)[0];
    let saved = player(&state, id).clone();
    let saved_elapsed = saved_at - started;
    let revision = saved.inventory.revision();
    // Spend ammunition, get hurt and move after the save; then die.
    state.set_action(
        id,
        Action {
            fire: true,
            back: true,
            ..Default::default()
        },
    );
    idle(&mut state, 20);
    state.players.iter_mut().find(|p| p.id == id).unwrap().armor = 3;
    die(&mut state, id);
    idle(&mut state, 40);
    let before = state.tick;
    let retry = request(&state);
    assert!(state.continue_mission(id, retry));
    assert!(state.tick >= before, "the tick never rewinds");
    let back = player(&state, id);
    assert_eq!([back.x, back.y, back.z], [saved.x, saved.y, saved.z]);
    assert_eq!(
        (back.yaw, back.hp, back.armor),
        (saved.yaw, saved.hp, saved.armor)
    );
    assert_eq!(back.weapon, saved.weapon);
    assert_eq!(
        back.inventory.saved_equipment(back.weapon),
        saved.inventory.saved_equipment(saved.weapon),
        "the checkpoint's weapons and rounds, not the spent ones"
    );
    assert!(
        back.inventory.revision() > revision,
        "inventory revision moves on"
    );
    let mission = state.mission_state().unwrap();
    mission.validate(state.tick).unwrap();
    let run = mission.run.unwrap();
    assert_eq!((run.status, run.continues), (CampaignRunStatus::Playing, 2));
    assert_eq!(mission.attempt, 2);
    assert_eq!(
        state.tick - state.campaign_attempt_started_at().unwrap(),
        saved_elapsed,
        "the level clock resumes where the checkpoint left it"
    );
    assert!(
        !state.continue_mission(id, retry),
        "a stale retry changes nothing"
    );
    // A second death returns to the same checkpoint again.
    die(&mut state, id);
    assert!(state.continue_mission(id, request(&state)));
    let again = player(&state, id);
    assert_eq!([again.x, again.z], [saved.x, saved.z]);
    assert_eq!(state.mission_state().unwrap().run.unwrap().continues, 1);
}

#[test]
fn without_a_checkpoint_a_continue_still_restores_the_level_entry() {
    let (mut state, id) = plain();
    let entry = player(&state, id).clone();
    state.set_action(
        id,
        Action {
            forward: true,
            ..Default::default()
        },
    );
    idle(&mut state, 20);
    die(&mut state, id);
    assert!(checkpoints(&state).is_empty());
    assert!(state.continue_mission(id, request(&state)));
    let back = player(&state, id);
    assert_eq!([back.x, back.z], [entry.x, entry.z]);
    assert_eq!(state.mission_state().unwrap().run.unwrap().continues, 2);
}

#[test]
fn exhaustion_after_a_checkpoint_ends_the_run_and_refuses_retry() {
    let (mut state, id) = plain();
    for _ in 0..3 {
        while checkpoints(&state).is_empty() {
            state.tick(0.05);
        }
        die(&mut state, id);
        assert!(state.continue_mission(id, request(&state)));
    }
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.hp = 0;
    state.tick(0.05);
    let run = state.mission_state().unwrap().run.unwrap();
    assert_eq!((run.status, run.continues), (CampaignRunStatus::Failed, 0));
    assert!(!state.continue_mission(id, request(&state)));
}

#[test]
fn a_woken_guard_blocks_the_save_and_its_defeat_asks_for_one() {
    let (mut state, id) = guarded();
    // Walk into the guard's region and wait out the minute in the fight.
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [player.x, player.z] = [0.0, -3.0];
    let started = state.campaign_attempt_started_at().unwrap();
    while state.tick < started + CHECKPOINT_INTERVAL_TICKS + 20 {
        state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 100;
        state.tick(0.05);
    }
    assert!(engaged(&state, id));
    assert!(checkpoints(&state).is_empty(), "no save with a guard awake");
    let guard = state
        .players
        .iter()
        .find(|p| p.campaign.is_some_and(|actor| actor.is_enemy()))
        .unwrap()
        .id;
    let cleared_at = state.tick;
    state.players.iter_mut().find(|p| p.id == guard).unwrap().hp = 0;
    // The kill hurts nobody; three quiet seconds after the last scratch the
    // checkpoint lands.
    idle(&mut state, CHECKPOINT_HURT_QUIET_TICKS + 2);
    let saved = checkpoints(&state);
    assert_eq!(saved.len(), 1);
    assert!(saved[0] > cleared_at && saved[0] <= cleared_at + CHECKPOINT_HURT_QUIET_TICKS + 2);
    assert_eq!(state.encounters.complete_count(), 1);
    // A death after the save keeps the group cleared: nobody stands up again.
    die(&mut state, id);
    assert!(state.continue_mission(id, request(&state)));
    idle(&mut state, 5);
    assert_eq!(state.encounters.complete_count(), 1);
    assert!(!state
        .players
        .iter()
        .any(|p| p.campaign.is_some_and(|actor| actor.is_enemy()) && p.hp > 0));
}

#[test]
fn a_death_before_the_group_clears_restores_the_dormant_guard_at_its_post() {
    let (mut state, id) = guarded();
    let started = state.campaign_attempt_started_at().unwrap();
    while checkpoints(&state).is_empty() {
        state.tick(0.05);
        assert!(state.tick < started + 2 * CHECKPOINT_INTERVAL_TICKS);
    }
    // Wake the guard after the save, then die.
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [player.x, player.z] = [0.0, -3.0];
    idle(&mut state, 10);
    assert!(engaged(&state, id));
    die(&mut state, id);
    assert!(state.continue_mission(id, request(&state)));
    assert!(!engaged(&state, id));
    idle(&mut state, 1);
    let guard = state
        .players
        .iter()
        .find(|p| p.campaign.is_some_and(|actor| actor.is_enemy()))
        .expect("the guard is placed again");
    assert_eq!([guard.x, guard.z], [5.0, -1.5]);
    assert!(
        guard.hp > 0,
        "the guard stands again, unhurt by the failed stretch"
    );
}

#[test]
fn a_far_woken_guard_that_lost_the_party_is_kept_where_it_stood() {
    let mut definition = super::super::tests::definition();
    definition["half_extent"] = json!(30);
    // The gate wall runs the full width, so the yard beyond it is out of sight.
    definition["solids"][1]["min"][0] = json!(-30);
    definition["solids"][2]["max"][0] = json!(30);
    definition["encounters"] = json!([{
        "id": "yard_watch",
        "regions": [{"min": [-6, 0, -8], "max": [6, 2, -4]}],
        "enemies": [{"id": "yard_clerk", "kind": "clerk", "feet": [5, 0, -1.5], "yaw": 3.0}]
    }]);
    let (mut state, id) = state_with(definition);
    idle(&mut state, 2);
    let guard = state
        .players
        .iter()
        .find(|p| p.campaign.is_some_and(|actor| actor.is_enemy()))
        .unwrap()
        .id;
    // The owner stands in the region: the group wakes. The guard is then far
    // off and has lost the party; it no longer blocks a save.
    let started = state.campaign_attempt_started_at().unwrap();
    while state.tick < started + CHECKPOINT_INTERVAL_TICKS {
        let body = state.players.iter_mut().find(|p| p.id == guard).unwrap();
        [body.x, body.z] = [25.0, 25.0];
        body.hp = 40;
        state.encounters.lose_track(state.tick);
        state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 100;
        state.tick(0.05);
    }
    let body = state.players.iter_mut().find(|p| p.id == guard).unwrap();
    [body.x, body.z] = [25.0, 25.0];
    body.hp = 40;
    state.encounters.lose_track(state.tick);
    assert!(state.encounters.is_awake(0));
    let mut waited = 0;
    while checkpoints(&state).is_empty() {
        let body = state.players.iter_mut().find(|p| p.id == guard).unwrap();
        [body.x, body.z] = [25.0, 25.0];
        state.encounters.lose_track(state.tick);
        state.tick(0.05);
        waited += 1;
        assert!(waited < 200, "a calm far guard does not block the save");
    }
    let kept = player(&state, guard).clone();
    // Hurt the guard and die; the retry has it back as saved.
    state.players.iter_mut().find(|p| p.id == guard).unwrap().hp = 5;
    die(&mut state, id);
    assert!(state.continue_mission(id, request(&state)));
    let back = player(&state, guard);
    assert_eq!(
        [back.x, back.z, back.hp as f32],
        [kept.x, kept.z, kept.hp as f32]
    );
    assert!(state.encounters.is_awake(0) && !state.encounters.is_complete(0));
    idle(&mut state, 2);
    assert!(state.players.iter().any(|p| p.id == guard && p.hp > 0));
}

fn engaged(state: &GameState, id: Uuid) -> bool {
    let me = player(state, id);
    state
        .encounters
        .engaged(&state.players, Some([me.x, me.y - PLAYER_FLOOR_Y, me.z]))
}
