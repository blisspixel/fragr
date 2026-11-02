//! A checkpoint written with the run file: save, reopen, retry and refusal.
use super::*;
use crate::maps::AuthoredMap;
use crate::mission::run_file::store::{RunProbe, RunStore};
use crate::mission::run_file::{RunDocument, SavedStep};
use crate::protocol::{Action, CampaignRunStatus, MissionId, MissionReady, Role};

const OWNER: Uuid = Uuid::from_u128(77);

fn map() -> std::sync::Arc<AuthoredMap> {
    let definition = super::super::tests::definition();
    AuthoredMap::read(serde_json::to_vec(&definition).unwrap().as_slice()).unwrap()
}

fn fresh() -> GameState {
    let mut state = GameState::with_authored_map(map());
    state.use_replay_ids();
    state.seed(7);
    state
}

fn ready(state: &mut GameState, attempt: u32) {
    assert!(state.acknowledge_mission(
        OWNER,
        MissionReady {
            id: MissionId::RecallNotice,
            attempt,
        },
    ));
}

/// A new run, walked off its spawn, hurt a little and saved once.
fn saved_run() -> (GameState, Player) {
    let mut state = fresh();
    state.enable_campaign_run().unwrap();
    state.add_player(OWNER, "Checkpoint test".into(), Role::Human);
    let player = &mut state.players[0];
    player.inventory.grant_weapon(WeaponType::Tack);
    player.weapon = WeaponType::Tack;
    ready(&mut state, 1);
    state.set_action(
        OWNER,
        Action {
            forward: true,
            ..Default::default()
        },
    );
    for _ in 0..12 {
        state.tick(0.05);
    }
    state.set_action(OWNER, Action::default());
    state.players[0].hp = 83;
    let started = state.campaign_attempt_started_at().unwrap();
    while state.campaign_checkpoint_ticks().is_empty() {
        state.tick(0.05);
        assert!(state.tick < started + 3 * CHECKPOINT_INTERVAL_TICKS);
    }
    let saved = state.players[0].clone();
    (state, saved)
}

/// Write `document` to a fresh run directory and read it back as a local
/// child would: the bytes on disk are the only thing that crosses.
fn through_disk(document: &RunDocument) -> RunDocument {
    let directory =
        std::env::temp_dir().join(format!("localexception-checkpoint-{}", Uuid::new_v4()));
    let hash = fresh().map.content_sha256().unwrap();
    let store = RunStore::open(&directory, hash).unwrap();
    store.save(document).unwrap();
    drop(store);
    let reopened = RunStore::open(&directory, hash).unwrap();
    let loaded = reopened.load().unwrap().unwrap();
    std::fs::remove_dir_all(&directory).unwrap();
    loaded
}

fn reopen(document: &RunDocument) -> GameState {
    let mut state = fresh();
    state.load_campaign_run(document).unwrap();
    state.add_player(OWNER, "Checkpoint test".into(), Role::Human);
    state
}

fn owner(state: &GameState) -> &Player {
    state.players.iter().find(|p| p.id == OWNER).unwrap()
}

#[test]
fn a_run_left_while_playing_reopens_at_its_checkpoint_without_spending_a_continue() {
    let (state, saved) = saved_run();
    let document = state.campaign_run_document().unwrap().unwrap();
    let checkpoint = document
        .checkpoint
        .clone()
        .expect("the checkpoint is saved");
    assert_eq!(checkpoint.mission, MissionId::RecallNotice);
    assert!(matches!(document.step, SavedStep::MissionEntry { .. }));
    let loaded = through_disk(&document);
    // The store reads the document as JSON first, so key order may differ.
    assert_eq!(
        serde_json::to_value(&loaded).unwrap(),
        serde_json::to_value(&document).unwrap()
    );
    let mut reopened = reopen(&loaded);
    assert!(
        reopened.tick >= checkpoint.tick,
        "the reopened clock starts at the save"
    );
    ready(&mut reopened, 1);
    reopened.take_events();
    reopened.tick(0.05);
    assert!(reopened
        .take_events()
        .iter()
        .any(|event| matches!(event, GameEvent::Checkpoint { resumed: true })));
    let back = owner(&reopened);
    assert_eq!([back.x, back.y, back.z], [saved.x, saved.y, saved.z]);
    assert_eq!(
        (back.hp, back.armor, back.weapon),
        (83, saved.armor, WeaponType::Tack)
    );
    assert_eq!(
        back.inventory.saved_equipment(back.weapon),
        saved.inventory.saved_equipment(saved.weapon)
    );
    let mission = reopened.mission_state().unwrap();
    mission.validate(reopened.tick).unwrap();
    let run = mission.run.unwrap();
    assert_eq!(
        (run.status, run.continues, mission.attempt),
        (CampaignRunStatus::Playing, 3, 1)
    );
    // The session's record starts at its own join and stays valid.
    reopened
        .player_record(OWNER)
        .unwrap()
        .validate_for(Some(OWNER), None)
        .unwrap();
    // The level clock resumes where the checkpoint left it.
    let elapsed = checkpoint.tick - state.campaign_attempt_started_at().unwrap();
    assert_eq!(
        reopened.tick - reopened.campaign_attempt_started_at().unwrap(),
        elapsed
    );
    // The same checkpoint stays on disk until the next one is taken.
    assert_eq!(
        reopened
            .campaign_run_document()
            .unwrap()
            .unwrap()
            .checkpoint,
        loaded.checkpoint
    );
}

#[test]
fn a_saved_death_spends_its_continue_at_the_checkpoint() {
    let (mut state, saved) = saved_run();
    state.set_action(
        OWNER,
        Action {
            back: true,
            ..Default::default()
        },
    );
    for _ in 0..20 {
        state.tick(0.05);
    }
    state.players[0].hp = 0;
    state.players[0].respawn_timer = Some(1);
    state.tick(0.05);
    let document = state.campaign_run_document().unwrap().unwrap();
    assert!(matches!(document.step, SavedStep::PendingContinue { .. }));
    assert!(document.checkpoint.is_some());
    let mut reopened = reopen(&through_disk(&document));
    reopened.tick(0.05);
    let mission = reopened.mission_state().unwrap();
    assert_eq!(mission.run.unwrap().status, CampaignRunStatus::Continue);
    assert!(reopened.continue_mission(
        OWNER,
        MissionContinue {
            id: MissionId::RecallNotice,
            run_id: mission.run.unwrap().id,
            attempt: mission.attempt,
        }
    ));
    let back = owner(&reopened);
    assert_eq!([back.x, back.y, back.z], [saved.x, saved.y, saved.z]);
    assert_eq!(back.hp, 83);
    reopened
        .player_record(OWNER)
        .unwrap()
        .validate_for(Some(OWNER), None)
        .unwrap();
    let mission = reopened.mission_state().unwrap();
    mission.validate(reopened.tick).unwrap();
    assert_eq!(
        (mission.run.unwrap().continues, mission.attempt),
        (2, 2),
        "one continue spent, the next attempt"
    );
}

#[test]
fn another_builds_or_a_damaged_checkpoint_is_refused_for_the_level_entry() {
    let (state, saved) = saved_run();
    let document = state.campaign_run_document().unwrap().unwrap();
    let mut entry_state = fresh();
    entry_state.enable_campaign_run().unwrap();
    entry_state.add_player(OWNER, "Entry".into(), Role::Human);
    let entry = owner(&entry_state).clone();
    let foreign = |edit: &dyn Fn(&mut SavedCheckpoint)| {
        let mut document = document.clone();
        edit(document.checkpoint.as_mut().unwrap());
        document
    };
    for document in [
        foreign(&|c| c.build = "0.0.1+elsewhere".into()),
        foreign(&|c| {
            c.state = std::sync::Arc::from(
                serde_json::value::to_raw_value(&serde_json::json!({"tick": 1})).unwrap(),
            )
        }),
        foreign(&|c| c.tick += 1),
    ] {
        let mut reopened = reopen(&through_disk(&document));
        ready(&mut reopened, 1);
        reopened.take_events();
        for _ in 0..3 {
            reopened.tick(0.05);
        }
        assert!(!reopened
            .take_events()
            .iter()
            .any(|event| matches!(event, GameEvent::Checkpoint { resumed: true })));
        let back = owner(&reopened);
        assert_eq!([back.x, back.z], [entry.x, entry.z], "the level entry");
        assert_ne!([back.x, back.z], [saved.x, saved.z]);
        assert_eq!(back.hp, entry.hp);
        assert_eq!(
            reopened
                .campaign_run_document()
                .unwrap()
                .unwrap()
                .checkpoint,
            None,
            "a refused checkpoint is dropped, never rewritten"
        );
    }
}

#[test]
fn a_checkpoint_for_another_mission_or_a_finished_level_is_invalid() {
    let (state, _) = saved_run();
    let mut document = state.campaign_run_document().unwrap().unwrap();
    let hash = fresh().map.content_sha256().unwrap();
    document.validate(hash).unwrap();
    let mut other = document.clone();
    other.checkpoint.as_mut().unwrap().mission = MissionId::PersonsUnknown;
    assert!(other.validate(hash).is_err());
    let SavedStep::MissionEntry { mission, entry } = document.step.clone() else {
        panic!("mission entry expected");
    };
    document.step = SavedStep::Failed { mission, entry };
    assert!(document.validate(hash).is_err());
}

#[test]
fn a_version_25_run_file_is_refused_as_incompatible() {
    let (state, _) = saved_run();
    let document = state.campaign_run_document().unwrap().unwrap();
    let hash = fresh().map.content_sha256().unwrap();
    let mut value = serde_json::to_value(&document).unwrap();
    assert_eq!(value["version"], 27);
    value["version"] = 25.into();
    value.as_object_mut().unwrap().remove("checkpoint");
    let bytes = serde_json::to_vec(&value).unwrap();
    assert!(matches!(
        RunStore::inspect_bytes(
            &bytes,
            [hash; crate::mission::run_file::store::CAMPAIGN_STAGES]
        ),
        RunProbe::Incompatible
    ));
}
