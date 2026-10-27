//! Isolated observer fixtures. Authored completion/status edits here are
//! calibration inputs, not earned market clears or supplied player actions.
use super::*;
use crate::campaign::{market_status, Scenario};
use fragr_server::maps::AuthoredSource;
use fragr_server::protocol::{
    AmmoPool, MagazineCount, MissionId, Role, WeaponType, M19_OBJECTIVE_IDS,
};
use fragr_server::session::GameSession;
use uuid::Uuid;

fn fixture() -> (MissionState, Status) {
    let mut session = GameSession::with_authored_map(
        AuthoredSource::Mission(MissionId::PlannedWorks)
            .load()
            .unwrap(),
    );
    session.state.enable_campaign_run().unwrap();
    let id = Uuid::from_u128(487);
    session
        .state
        .add_player(id, "Receipt fixture".into(), Role::Human);
    session.state.arm_joined_magazines(id);
    (
        session.state.mission_state().unwrap(),
        market_status(&session, id).unwrap(),
    )
}

fn completed(state: &mut MissionState, count: usize) {
    let facts = state.m19.as_mut().unwrap();
    facts.completed = M19_OBJECTIVE_IDS[..count]
        .iter()
        .map(|id| (*id).into())
        .collect();
    facts.current.as_mut().unwrap().id = M19_OBJECTIVE_IDS[count].into();
}

#[test]
fn receipts_preserve_complete_own_equipment_and_stage_boundaries() {
    let (mut state, status) = fixture();
    let original = state.clone();
    let mut recorder = Recorder::default();
    recorder.observe(0, &state, Some(status.clone()));
    assert_eq!(state, original, "observation cannot change mission facts");
    completed(&mut state, 4);
    let mut earned = status.clone();
    // Deliberately distinct fixture values verify custody of the entire
    // loadout, including reload state, claims and every non-bullet pool.
    earned.hp = 63;
    earned.armor = 12;
    earned.loadout.tick = 80;
    earned.loadout.weapons = vec![
        WeaponType::Fists,
        WeaponType::Flechette,
        WeaponType::Scatter,
        WeaponType::Rail,
        WeaponType::Rocket,
    ];
    earned.loadout.selected = WeaponType::Flechette;
    for count in &mut earned.loadout.ammo {
        count.rounds = match count.pool {
            AmmoPool::Bullets => 15,
            AmmoPool::Shells => 20,
            AmmoPool::Cells => 30,
            AmmoPool::Rockets => 4,
        };
    }
    earned.loadout.loaded = vec![
        MagazineCount {
            weapon: WeaponType::Flechette,
            rounds: 0,
            ready_at: Some(90),
        },
        MagazineCount {
            weapon: WeaponType::Scatter,
            rounds: 3,
            ready_at: None,
        },
        MagazineCount {
            weapon: WeaponType::Rail,
            rounds: 1,
            ready_at: None,
        },
        MagazineCount {
            weapon: WeaponType::Rocket,
            rounds: 1,
            ready_at: None,
        },
    ];
    earned.loadout.grenades = 2;
    earned.loadout.proximity_mines = 1;
    earned.loadout.remote_mines = 2;
    earned.loadout.personal_claims = vec!["fixture-earned".into()];
    earned.loadout.dry_fire_count = 4;
    recorder.observe(80, &state, Some(earned.clone()));
    completed(&mut state, 5);
    recorder.observe(81, &state, Some(earned.clone()));
    recorder.observe(81, &state, Some(earned.clone()));
    recorder.finish_attempt(81, &state, Some(earned.clone()));
    let rows = recorder.finish().attempts;
    assert_eq!(rows.len(), 1);
    let row = &rows[0];
    assert!(row.entered_market);
    assert_eq!(row.outcome, Outcome::Complete);
    assert_eq!(
        row.receipts.iter().map(|r| r.event).collect::<Vec<_>>(),
        [Event::Entry, Event::MarketEntry, Event::MarketComplete]
    );
    assert_eq!(row.receipts[0].status.as_ref(), Some(&status));
    assert_eq!(row.receipts[1].status.as_ref(), Some(&earned));
    assert_eq!(row.receipts[2].status.as_ref(), Some(&earned));
    assert_eq!(
        row.receipts[1].current_objective.as_deref(),
        Some("market_strips")
    );
    assert_eq!(
        row.receipts[2].current_objective.as_deref(),
        Some("water_tanks")
    );
    assert_eq!(row.receipts[2].tick, 81);
    assert_eq!(row.receipts[0].continues, Some(3));
    assert_eq!(status.loadout.weapons, [WeaponType::Fists]);
    assert!(status.loadout.ammo.iter().all(|pool| pool.rounds == 0));
}

#[test]
fn endpoint_requires_the_market_boundary_and_a_living_nonfailed_attempt() {
    let (mut state, mut status) = fixture();
    completed(&mut state, 4);
    assert!(Scenario::M19Teaching.segment_complete(&state, true));
    assert!(!Scenario::M19Market.segment_complete(&state, true));
    assert!(!Scenario::RecallNotice.segment_complete(&state, true));
    completed(&mut state, 5);
    assert!(Scenario::M19Market.segment_complete(&state, true));
    assert!(!Scenario::M19Market.segment_complete(&state, false));
    for failed in [CampaignRunStatus::Continue, CampaignRunStatus::Failed] {
        state.run.as_mut().unwrap().status = failed;
        assert!(!Scenario::M19Market.segment_complete(&state, true));
        status.hp = 0;
        let mut recorder = Recorder::default();
        recorder.observe(50, &state, Some(status.clone()));
        recorder.finish_attempt(50, &state, Some(status.clone()));
        let row = recorder.finish().attempts.pop().unwrap();
        assert_ne!(row.outcome, Outcome::Complete);
        assert!(!row
            .receipts
            .iter()
            .any(|r| r.event == Event::MarketComplete));
    }
    state.m19 = None;
    assert!(!Scenario::M19Market.segment_complete(&state, true));
}

#[test]
fn death_before_market_and_exhaustion_inside_market_remain_separate_attempts() {
    let (mut state, status) = fixture();
    let mut recorder = Recorder::default();
    for attempt in 1..=4 {
        state.attempt = attempt;
        let run = state.run.as_mut().unwrap();
        run.status = CampaignRunStatus::Playing;
        run.continues = (4 - attempt) as u8;
        completed(&mut state, 0);
        recorder.observe(u64::from(attempt * 10), &state, Some(status.clone()));
        if attempt > 1 {
            completed(&mut state, 4);
            recorder.observe(u64::from(attempt * 10 + 1), &state, Some(status.clone()));
        }
        state.run.as_mut().unwrap().status = if attempt == 4 {
            CampaignRunStatus::Failed
        } else {
            CampaignRunStatus::Continue
        };
        let mut dead = status.clone();
        dead.hp = 0;
        recorder.observe(u64::from(attempt * 10 + 2), &state, Some(dead.clone()));
        recorder.observe(u64::from(attempt * 10 + 2), &state, Some(dead));
    }
    let rows = recorder.finish().attempts;
    assert_eq!(rows.len(), 4);
    assert!(!rows[0].entered_market);
    assert!(rows[1..].iter().all(|row| row.entered_market));
    assert!(rows[..3].iter().all(|row| row.outcome == Outcome::Death));
    assert_eq!(rows[3].outcome, Outcome::Exhausted);
    for (index, row) in rows.iter().enumerate() {
        let terminal = row.receipts.last().unwrap();
        assert_eq!(terminal.continues, Some((3 - index) as u8));
        assert_eq!(terminal.status.as_ref().unwrap().hp, 0);
        assert_eq!(row.receipts.len(), if index == 0 { 2 } else { 3 });
    }
}

#[test]
fn attempt_flags_never_become_unearned_market_attribution() {
    let (mut state, status) = fixture();
    let mut recorder = Recorder::default();
    recorder.observe(0, &state, Some(status.clone()));
    state.m19.as_mut().unwrap().challenges.paver_interrupted = true;
    completed(&mut state, 4);
    recorder.observe(1, &state, Some(status.clone()));
    state.m19.as_mut().unwrap().challenges.strip_struck = true;
    recorder.observe(2, &state, Some(status.clone()));
    recorder.finish_attempt(3, &state, Some(status.clone()));
    let first = &recorder.metrics.attempts[0];
    assert_eq!(first.interruption, Attribution::Unknown);
    assert_eq!(first.strip_damage, Attribution::FirstObservedDuringMarket);
    assert!(first.receipts[1].attempt_paver_interrupted);
    state.attempt = 2;
    completed(&mut state, 4);
    recorder.observe(10, &state, Some(status.clone()));
    recorder.finish_attempt(10, &state, Some(status));
    let second = &recorder.metrics.attempts[1];
    assert_eq!(second.interruption, Attribution::Unknown);
    assert_eq!(second.strip_damage, Attribution::Unknown);
}

#[test]
fn timeout_and_missing_participant_facts_do_not_invent_completion_or_equipment() {
    let (mut state, status) = fixture();
    for entered in [false, true] {
        let mut recorder = Recorder::default();
        completed(&mut state, if entered { 4 } else { 0 });
        recorder.observe(10, &state, Some(status.clone()));
        recorder.finish_attempt(20, &state, None);
        recorder.finish_attempt(20, &state, None);
        let row = recorder.finish().attempts.pop().unwrap();
        assert_eq!(row.outcome, Outcome::Timeout);
        assert_eq!(row.entered_market, entered);
        assert!(row.receipts.last().unwrap().status.is_none());
    }
    completed(&mut state, 5);
    let mut recorder = Recorder::default();
    recorder.observe(50, &state, None);
    recorder.finish_attempt(50, &state, None);
    assert_eq!(recorder.finish().attempts[0].outcome, Outcome::Timeout);
    state.m19 = None;
    let mut recorder = Recorder::default();
    recorder.observe(0, &state, Some(status));
    recorder.finish_attempt(1, &state, None);
    assert!(recorder.finish().attempts.is_empty());
}

#[test]
fn tanks_continuation_keeps_market_completion_and_separates_its_own_failures() {
    let (mut state, status) = fixture();
    let mut recorder = Recorder::through_tanks();
    recorder.observe(0, &state, Some(status.clone()));
    completed(&mut state, 4);
    recorder.observe(10, &state, Some(status.clone()));
    completed(&mut state, 5);
    recorder.observe(20, &state, Some(status.clone()));
    recorder.observe(21, &state, Some(status.clone()));
    let row = &recorder.metrics.attempts[0];
    assert_eq!(
        row.outcome,
        Outcome::InProgress,
        "market is not the endpoint"
    );
    assert!(
        recorder.in_market(),
        "continuation steps are still recorded"
    );
    assert!(row.continuation.is_some());
    assert_eq!(
        row.receipts
            .iter()
            .filter(|r| r.event == Event::MarketComplete)
            .count(),
        1
    );
    // A strip flag first seen on the continuation carries no market timing.
    state.m19.as_mut().unwrap().challenges.strip_struck = true;
    recorder.observe(30, &state, Some(status.clone()));
    assert_eq!(
        recorder.metrics.attempts[0].strip_damage,
        Attribution::Unknown
    );
    // Death on the way to the tanks: an ordinary failed attempt.
    state.run.as_mut().unwrap().status = CampaignRunStatus::Continue;
    let mut dead = status.clone();
    dead.hp = 0;
    recorder.observe(40, &state, Some(dead.clone()));
    let row = &recorder.metrics.attempts[0];
    assert_eq!(row.outcome, Outcome::Death);
    assert_eq!(
        row.receipts.last().unwrap().current_objective.as_deref(),
        Some("water_tanks")
    );
    // The retry starts again from entry and must earn the market again.
    state.attempt = 2;
    state.run.as_mut().unwrap().status = CampaignRunStatus::Playing;
    completed(&mut state, 0);
    recorder.observe(50, &state, Some(status.clone()));
    let rows = recorder.finish().attempts;
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[1].outcome, Outcome::InProgress);
    assert!(!rows[1].entered_market, "no market without tram_street");
    let (mut state, status) = fixture();
    let mut recorder = Recorder::through_tanks();
    completed(&mut state, 6);
    recorder.observe(5, &state, Some(status.clone()));
    let row = recorder.finish().attempts.pop().unwrap();
    assert_eq!(row.outcome, Outcome::Complete);
    assert_eq!(
        row.receipts.iter().map(|r| r.event).collect::<Vec<_>>(),
        [
            Event::Entry,
            Event::MarketEntry,
            Event::MarketComplete,
            Event::TanksComplete
        ]
    );
    assert_eq!(
        row.receipts[3].current_objective.as_deref(),
        Some("roof_loop")
    );
}

#[test]
fn per_action_market_facts_start_at_public_entry_and_stop_at_the_terminal_receipt() {
    let (mut state, mut status) = fixture();
    let mut recorder = Recorder::default();
    recorder.observe(0, &state, Some(status.clone()));
    assert!(
        !recorder.in_market(),
        "the teaching prefix has no stage facts"
    );
    assert!(recorder.metrics.attempts[0].stage.is_none());
    completed(&mut state, 4);
    status.loadout.weapons = vec![WeaponType::Fists, WeaponType::Flechette];
    for count in &mut status.loadout.ammo {
        count.rounds = if count.pool == AmmoPool::Bullets {
            9
        } else {
            12
        };
    }
    recorder.observe(5, &state, Some(status.clone()));
    assert!(recorder.in_market());
    let entry = recorder.metrics.attempts[0].stage.as_ref().unwrap();
    assert_eq!(entry.entry_ranged_rounds, 9, "shells need a Scatter");
    completed(&mut state, 5);
    recorder.observe(9, &state, Some(status.clone()));
    assert!(
        !recorder.in_market(),
        "completion ends per-action recording"
    );
    let names = std::collections::BTreeMap::new();
    recorder.step(
        &stage::Decision {
            tick: 9,
            feet: status.feet,
            hp: 100,
            armor: 0,
            airborne: false,
            moving: false,
            telling: false,
            guard: None,
            recognized: Vec::new(),
            strips: &[],
            names: &names,
        },
        stage::Outcome {
            strips: &[],
            status: Some(status),
            shots: Vec::new(),
        },
    );
    let row = &recorder.finish().attempts[0];
    assert_eq!(row.outcome, Outcome::Complete);
    assert_eq!(row.stage.as_ref().unwrap().decision_steps, 0);
}

#[test]
fn terminal_and_continuation_boundaries_close_open_market_contacts() {
    let (mut state, status) = fixture();
    let names = std::collections::BTreeMap::new();
    let strip = fragr_server::protocol::PaverStripState {
        owner_id: Uuid::from_u128(7),
        origin: [status.feet[0] - 1.0, status.feet[1], status.feet[2]],
        yaw: 0.0,
        length: 4.0,
        half_width: 1.6,
        working: false,
        phase_started: 0,
        phase_ends: 40,
    };
    let stand = |recorder: &mut Recorder, tick| {
        recorder.step(
            &stage::Decision {
                tick,
                feet: status.feet,
                hp: 100,
                armor: 0,
                airborne: false,
                moving: false,
                telling: false,
                guard: None,
                recognized: Vec::new(),
                strips: &[strip],
                names: &names,
            },
            stage::Outcome {
                strips: &[strip],
                status: Some(status.clone()),
                shots: Vec::new(),
            },
        )
    };
    for through_tanks in [false, true] {
        let mut recorder = if through_tanks {
            Recorder::through_tanks()
        } else {
            Recorder::default()
        };
        completed(&mut state, 4);
        recorder.observe(1, &state, Some(status.clone()));
        stand(&mut recorder, 2);
        completed(&mut state, 5);
        recorder.observe(3, &state, Some(status.clone()));
        let row = &recorder.metrics.attempts[0];
        let market = row.stage.as_ref().unwrap();
        assert_eq!(market.contacts.len(), 1);
        assert_eq!(market.contacts[0].left_tick, Some(3));
        if through_tanks {
            stand(&mut recorder, 4);
            recorder.finish_attempt(5, &state, Some(status.clone()));
            let row = &recorder.metrics.attempts[0];
            let continuation = row.continuation.as_ref().unwrap();
            assert_eq!(continuation.contacts[0].left_tick, Some(5));
        }
    }
}
