//! Isolated observer calibration. Samples below deliberately set position,
//! fuel, outcomes and phases; they are not earned movement or campaign clears.
use super::*;
use crate::campaign::PROFILES;
use fragr_server::maps::AuthoredSource;
use fragr_server::protocol::{
    CampaignActor, ControlDomain, EnemyKind, EnemyPhase, JetpackState, MissionId, PaverStripState,
    Role,
};
use fragr_server::session::GameSession;

const GALLERY: [f32; 3] = [-49.0, 4.5, -6.0];
const ABOVE_GALLERY: [f32; 3] = [-49.0, 5.1, -6.0];
const ASCENDING: [f32; 3] = [-49.0, 1.85, -14.5];
const GROUND: [f32; 3] = [-55.0, 0.0, -26.0];

struct Fixture {
    id: Uuid,
    snapshot: Snapshot,
    state: MissionState,
    arena: Arena,
    map_info: ServerMessage,
}

impl Fixture {
    fn new() -> Self {
        let mut session = GameSession::with_authored_map(
            AuthoredSource::Mission(MissionId::PlannedWorks)
                .load()
                .unwrap(),
        );
        let id = Uuid::from_u128(485);
        session.state.use_replay_ids();
        session
            .state
            .add_player(id, "Observer fixture".into(), Role::Human);
        Self {
            id,
            snapshot: session.state.snapshot(),
            state: session.state.mission_state().unwrap(),
            arena: session.state.map.arena().clone(),
            map_info: session.state.map_info(),
        }
    }

    fn recorder(&self, record: bool) -> Recorder {
        Recorder::new(
            self.id,
            42,
            PROFILES[1],
            CampaignDifficulty::Standard,
            record,
        )
    }

    fn frame(&self, tick: u64, feet: [f32; 3], pack: Option<(u16, bool)>) -> Snapshot {
        let mut frame = self.snapshot.clone();
        frame.tick = tick;
        frame.players.retain(|player| player.id == self.id);
        let player = &mut frame.players[0];
        player.x = feet[0];
        player.y = feet[1] + PLAYER_FLOOR_Y;
        player.z = feet[2];
        player.hp = 100;
        frame.jetpacks = pack
            .map(|(fuel, thrusting)| JetpackState {
                player_id: self.id,
                fuel,
                thrusting,
            })
            .into_iter()
            .collect();
        frame.paver_strips.clear();
        frame
    }

    fn observe(&self, recorder: &mut Recorder, frame: &Snapshot, vy: f32) -> bool {
        recorder.observe(frame, &self.state, &self.arena, Some(vy), &self.map_info)
    }
}

fn add_strip(frame: &mut Snapshot, started: u64, working: bool) {
    let owner = Uuid::from_u128(486);
    let mut actor = frame.players[0].clone();
    actor.id = owner;
    actor.x = 4.0;
    actor.y = PLAYER_FLOOR_Y;
    actor.z = -16.0;
    actor.body = None;
    actor.weapon = "Fists".into();
    actor.campaign = Some(CampaignActor::Hostile {
        kind: EnemyKind::Paver,
        phase: if working {
            EnemyPhase::Firing
        } else {
            EnemyPhase::Windup
        },
        phase_started: started,
        phase_ends: started + if working { 12 } else { 34 },
        seated: false,
        control: ControlDomain::Restoration,
    });
    frame.players.push(actor);
    frame.paver_strips.push(PaverStripState {
        owner_id: owner,
        origin: [3.1, 0.0, -16.0],
        yaw: std::f32::consts::PI,
        length: 15.0,
        half_width: 1.6,
        working,
        phase_started: started,
        phase_ends: started + if working { 12 } else { 34 },
    });
}

fn add_second_strip(frame: &mut Snapshot) {
    let first = frame.paver_strips[0];
    let mut owner = frame
        .players
        .iter()
        .find(|player| player.id == first.owner_id)
        .unwrap()
        .clone();
    owner.id = Uuid::from_u128(487);
    owner.x += 5.0;
    let mut second = first;
    second.owner_id = owner.id;
    second.origin[0] += 5.0;
    frame.players.push(owner);
    frame.paver_strips.push(second);
}

fn enter_market(fixture: &mut Fixture) {
    fixture.state.m19.as_mut().unwrap().completed = [
        "concourse_stores",
        "broken_stair",
        "concourse_crossing",
        "tram_street",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect();
    let ServerMessage::MapInfo {
        m19: Some(geometry),
        ..
    } = &fixture.map_info
    else {
        panic!("fixture requires authored M19 geometry");
    };
    fixture.state.m19.as_mut().unwrap().current = Some(geometry.objectives[4].clone());
}

#[test]
fn airborne_objective_receipt_is_not_a_supported_gallery_landing() {
    let mut fixture = Fixture::new();
    let mut recorder = fixture.recorder(true);
    fixture.observe(
        &mut recorder,
        &fixture.frame(1, GROUND, Some((60, false))),
        0.0,
    );
    fixture.observe(
        &mut recorder,
        &fixture.frame(2, ASCENDING, Some((60, false))),
        7.0,
    );
    fixture.state.m19.as_mut().unwrap().completed =
        vec!["concourse_stores".into(), "broken_stair".into()];
    assert!(fixture.observe(
        &mut recorder,
        &fixture.frame(3, ABOVE_GALLERY, Some((59, true))),
        2.0,
    ));
    assert_eq!(recorder.metrics.objectives.len(), 2);
    assert_eq!(recorder.metrics.objectives[1].feet, ABOVE_GALLERY);
    assert!(!recorder.metrics.flights[0].gallery_landing);
    assert_eq!(recorder.metrics.flights[0].ending, "airborne");
    assert!(!fixture.observe(
        &mut recorder,
        &fixture.frame(4, ABOVE_GALLERY, Some((58, true))),
        -1.0,
    ));
    fixture.observe(
        &mut recorder,
        &fixture.frame(5, GALLERY, Some((58, false))),
        0.0,
    );
    let (metrics, _) = recorder.finish();
    assert_eq!(metrics.flights.len(), 1);
    let flight = &metrics.flights[0];
    assert_eq!(flight.ending, "supported");
    assert!(flight.gallery_landing);
    assert_eq!(flight.burn_ticks, 2);
    assert_eq!((flight.initial_fuel, flight.minimum_fuel), (60, 58));
    assert_eq!((flight.started_tick, flight.ended_tick), (2, 5));
    assert!(flight
        .from
        .iter()
        .zip(ASCENDING)
        .all(|(actual, expected)| (*actual - expected).abs() <= 1e-6));
    assert_eq!(flight.to, GALLERY);
}

#[test]
fn lower_ground_or_an_unpowered_fall_never_qualifies_the_jetpack_lesson() {
    for (burn, destination) in [(true, GROUND), (false, GALLERY)] {
        let fixture = Fixture::new();
        let mut recorder = fixture.recorder(false);
        fixture.observe(
            &mut recorder,
            &fixture.frame(10, ABOVE_GALLERY, Some((45, burn))),
            -1.0,
        );
        fixture.observe(
            &mut recorder,
            &fixture.frame(11, destination, Some((45, false))),
            0.0,
        );
        let (metrics, _) = recorder.finish();
        assert_eq!(metrics.flights[0].ending, "supported");
        assert!(
            !metrics.flights[0].gallery_landing,
            "burn={burn}, destination={destination:?}"
        );
    }
}

#[test]
fn gallery_hops_or_an_already_high_falling_burn_do_not_qualify_as_an_ascent() {
    let fixture = Fixture::new();
    for began_supported in [false, true] {
        let mut recorder = fixture.recorder(false);
        if began_supported {
            fixture.observe(
                &mut recorder,
                &fixture.frame(1, GALLERY, Some((60, false))),
                0.0,
            );
        }
        fixture.observe(
            &mut recorder,
            &fixture.frame(2, ABOVE_GALLERY, Some((59, true))),
            if began_supported { 1.0 } else { -1.0 },
        );
        fixture.observe(
            &mut recorder,
            &fixture.frame(3, GALLERY, Some((59, false))),
            0.0,
        );
        let (metrics, _) = recorder.finish();
        let flight = &metrics.flights[0];
        assert_eq!(flight.ending, "supported");
        assert_eq!(flight.burn_ticks, 1);
        assert_eq!(flight.to, GALLERY);
        assert!(
            !flight.gallery_landing,
            "a gallery hop or falling burn is not the lower-to-gallery lesson"
        );
    }
}

#[test]
fn losing_the_pack_ends_the_flight_before_a_later_supported_reacquisition() {
    let fixture = Fixture::new();
    let mut recorder = fixture.recorder(false);
    fixture.observe(
        &mut recorder,
        &fixture.frame(1, ASCENDING, Some((50, true))),
        1.0,
    );
    fixture.observe(&mut recorder, &fixture.frame(2, ABOVE_GALLERY, None), -1.0);
    fixture.observe(
        &mut recorder,
        &fixture.frame(3, GALLERY, Some((50, false))),
        0.0,
    );
    let (metrics, _) = recorder.finish();
    assert_eq!(metrics.flights.len(), 1);
    let flight = &metrics.flights[0];
    assert_eq!(flight.ending, "pack_missing");
    assert_eq!(flight.ended_tick, 1);
    assert!(flight
        .to
        .iter()
        .zip(ASCENDING)
        .all(|(actual, expected)| (*actual - expected).abs() <= 1e-6));
    assert!(flight.burn_ticks > 0);
    assert!(!flight.gallery_landing);
    assert_eq!(metrics.supported_refuel_ticks, 0);
    assert_eq!(metrics.airborne_refuel_ticks, 0);
}

#[test]
fn retry_death_and_trial_end_close_flights_without_inventing_landings() {
    for ending in ["retry", "death", "trial_end"] {
        let mut fixture = Fixture::new();
        let mut recorder = fixture.recorder(true);
        fixture.observe(
            &mut recorder,
            &fixture.frame(10, ABOVE_GALLERY, Some((50, true))),
            1.0,
        );
        match ending {
            "retry" => {
                fixture.state.attempt += 1;
                fixture.observe(&mut recorder, &fixture.frame(11, GROUND, None), 0.0);
            }
            "death" => {
                let mut dead = fixture.frame(11, ABOVE_GALLERY, Some((50, false)));
                dead.players[0].hp = 0;
                fixture.observe(&mut recorder, &dead, -1.0);
            }
            _ => {}
        }
        let (metrics, _) = recorder.finish();
        assert_eq!(metrics.flights.len(), 1);
        assert_eq!(metrics.flights[0].ending, ending);
        assert!(!metrics.flights[0].gallery_landing);
    }
}

#[test]
fn refuel_counts_compare_only_continuous_live_pack_observations() {
    for reset in ["retry", "acquisition", "death"] {
        let mut fixture = Fixture::new();
        let mut recorder = fixture.recorder(false);
        fixture.observe(
            &mut recorder,
            &fixture.frame(1, GROUND, Some((10, false))),
            0.0,
        );
        match reset {
            "retry" => fixture.state.attempt += 1,
            "acquisition" => {
                fixture.observe(&mut recorder, &fixture.frame(2, GROUND, None), 0.0);
            }
            _ => {
                let mut dead = fixture.frame(2, GROUND, Some((10, false)));
                dead.players[0].hp = 0;
                fixture.observe(&mut recorder, &dead, 0.0);
            }
        }
        fixture.observe(
            &mut recorder,
            &fixture.frame(3, ABOVE_GALLERY, Some((40, false))),
            1.0,
        );
        assert_eq!(
            recorder.metrics.airborne_refuel_ticks, 0,
            "{reset} is not air refuel"
        );
        assert_eq!(
            recorder.metrics.supported_refuel_ticks, 0,
            "{reset} is not supported refuel"
        );
        fixture.observe(
            &mut recorder,
            &fixture.frame(4, ABOVE_GALLERY, Some((41, false))),
            -1.0,
        );
        fixture.observe(
            &mut recorder,
            &fixture.frame(5, GALLERY, Some((44, false))),
            0.0,
        );
        let (metrics, _) = recorder.finish();
        assert_eq!(
            metrics.airborne_refuel_ticks, 1,
            "a real anomalous increase remains visible"
        );
        assert_eq!(metrics.supported_refuel_ticks, 1);
    }
}

#[test]
fn strip_recognition_is_later_than_authoritative_first_sighting_and_attempt_local() {
    let mut fixture = Fixture::new();
    let mut recorder = fixture.recorder(true);
    let mut tell = fixture.frame(10, GROUND, Some((60, false)));
    add_strip(&mut tell, 8, false);
    fixture.observe(&mut recorder, &tell, 0.0);
    recorder.observe_perception(&fixture.frame(10, GROUND, Some((60, false))));
    assert_eq!(recorder.metrics.paver_phases[0].recognized_tick, None);
    tell.tick = 13;
    recorder.observe_perception(&tell);
    tell.tick = 14;
    recorder.observe_perception(&tell);
    let first = &recorder.metrics.paver_phases[0];
    assert_eq!(
        (
            first.started_tick,
            first.first_snapshot_tick,
            first.recognized_tick
        ),
        (8, 10, Some(13))
    );
    let mut work = fixture.frame(21, GROUND, Some((60, false)));
    add_strip(&mut work, 20, true);
    fixture.observe(&mut recorder, &work, 0.0);
    work.tick = 25;
    recorder.observe_perception(&work);
    assert_eq!(recorder.metrics.paver_phases[1].recognized_tick, Some(25));
    fixture.state.attempt += 1;
    tell.tick = 26;
    fixture.observe(&mut recorder, &tell, 0.0);
    let (metrics, _) = recorder.finish();
    assert_eq!(metrics.paver_phases.len(), 3);
    assert_eq!(metrics.paver_phases[2].attempt, fixture.state.attempt);
    assert_eq!(metrics.paver_phases[2].recognized_tick, None);
}

#[test]
fn teaching_windows_are_bounded_consecutive_and_cannot_cross_retry() {
    let mut fixture = Fixture::new();
    let mut recorder = fixture.recorder(true);
    for tick in 1..=200 {
        fixture.observe(
            &mut recorder,
            &fixture.frame(tick, ABOVE_GALLERY, Some((40, tick == 1))),
            -1.0,
        );
    }
    fixture.state.attempt += 1;
    fixture.observe(
        &mut recorder,
        &fixture.frame(201, ABOVE_GALLERY, Some((59, true))),
        1.0,
    );
    fixture.observe(
        &mut recorder,
        &fixture.frame(202, GALLERY, Some((59, false))),
        0.0,
    );
    let (_, windows) = recorder.finish();
    assert_eq!(windows.len(), 2);
    assert_eq!(windows[0]["frames"].as_array().unwrap().len(), 160);
    assert_eq!(windows[0]["frames"][0]["tick"], 1);
    assert_eq!(windows[0]["frames"][159]["tick"], 160);
    assert_eq!(windows[1]["frames"][0]["tick"], 201);
    assert_ne!(windows[0]["attempt"], windows[1]["attempt"]);
    for window in windows {
        let frames = window["frames"].as_array().unwrap();
        assert!(frames.len() <= 160);
        assert!(
            frames
                .windows(2)
                .all(|pair| pair[0]["tick"].as_u64().unwrap() + 1
                    == pair[1]["tick"].as_u64().unwrap())
        );
    }
}

#[test]
fn an_ordinary_jump_does_not_consume_the_later_recorded_burn_window() {
    let fixture = Fixture::new();
    let mut recorder = fixture.recorder(true);
    for tick in 1..=180 {
        fixture.observe(
            &mut recorder,
            &fixture.frame(tick, ABOVE_GALLERY, Some((60, false))),
            -1.0,
        );
    }
    fixture.observe(
        &mut recorder,
        &fixture.frame(181, GALLERY, Some((60, false))),
        0.0,
    );
    fixture.observe(
        &mut recorder,
        &fixture.frame(182, ABOVE_GALLERY, Some((59, true))),
        1.0,
    );
    let (_, windows) = recorder.finish();
    assert_eq!(windows.len(), 1);
    let frames = windows[0]["frames"].as_array().unwrap();
    assert!(frames.iter().any(|frame| frame["jetpacks"]
        .as_array()
        .is_some_and(|packs| packs.iter().any(|pack| pack["thrusting"] == true))));
    assert_eq!(frames.last().unwrap()["tick"], 182);
}

#[test]
fn a_gap_does_not_enter_a_new_teaching_window() {
    let fixture = Fixture::new();
    let mut recorder = fixture.recorder(true);
    fixture.observe(
        &mut recorder,
        &fixture.frame(1, GROUND, Some((60, false))),
        0.0,
    );
    fixture.observe(
        &mut recorder,
        &fixture.frame(3, ABOVE_GALLERY, Some((59, true))),
        1.0,
    );
    let (_, windows) = recorder.finish();
    let frames = windows[0]["frames"].as_array().unwrap();
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0]["tick"], 3);
}

#[test]
fn disabling_recording_preserves_every_observer_metric() {
    let mut fixture = Fixture::new();
    let mut recorded = fixture.recorder(true);
    let mut unrecorded = fixture.recorder(false);
    for tick in 1..=5 {
        let feet = match tick {
            1 => ASCENDING,
            2 | 3 => ABOVE_GALLERY,
            _ => GALLERY,
        };
        let mut frame = fixture.frame(tick, feet, Some((50 - tick as u16, tick < 4)));
        add_strip(&mut frame, 1, false);
        if tick == 3 {
            fixture.state.m19.as_mut().unwrap().completed =
                vec!["concourse_stores".into(), "broken_stair".into()];
        }
        if tick == 5 {
            let challenges = &mut fixture.state.m19.as_mut().unwrap().challenges;
            challenges.paver_interrupted = true;
            challenges.strip_struck = true;
        }
        for recorder in [&mut recorded, &mut unrecorded] {
            fixture.observe(recorder, &frame, if tick < 4 { 1.0 } else { 0.0 });
            if tick >= 2 {
                recorder.observe_perception(&frame);
            }
        }
    }
    let (recorded_metrics, windows) = recorded.finish();
    let (unrecorded_metrics, absent) = unrecorded.finish();
    assert_eq!(recorded_metrics, unrecorded_metrics);
    assert!(recorded_metrics.flights[0].gallery_landing);
    assert!(!windows.is_empty());
    assert!(absent.is_empty());
    assert_eq!(
        recorded_metrics.interrupted_attempts,
        vec![fixture.state.attempt]
    );
    assert_eq!(
        recorded_metrics.strip_struck_attempts,
        vec![fixture.state.attempt]
    );
}

#[test]
fn active_stall_windows_require_a_live_threshold_and_are_recording_only() {
    let fixture = Fixture::new();
    for record in [false, true] {
        let mut recorder = fixture.recorder(record);
        let frame = fixture.frame(1, GROUND, Some((60, false)));
        fixture.observe(&mut recorder, &frame, 0.0);
        let me = &frame.players[0];
        for seconds in [0.0, 9.99, f64::NAN, f64::INFINITY] {
            recorder.observe_stall(seconds, me, &fixture.map_info);
        }
        let mut dead = me.clone();
        dead.hp = 0;
        recorder.observe_stall(10.0, &dead, &fixture.map_info);
        assert!(recorder.windows.is_empty());
        recorder.observe_stall(10.0, me, &fixture.map_info);
        recorder.observe_stall(10.0, me, &fixture.map_info);
        recorder.observe_stall(20.0, me, &fixture.map_info);
        let (metrics, windows) = recorder.finish();
        assert_eq!(metrics, Metrics::default());
        if record {
            assert_eq!(windows.len(), 1);
            assert_eq!(windows[0]["event"], "active_stall");
            assert_eq!(windows[0]["active_stall_seconds"], 10.0);
            assert_eq!(windows[0]["frames"].as_array().unwrap().len(), 1);
            assert_eq!(windows[0]["frames"][0]["tick"], 1);
        } else {
            assert!(windows.is_empty());
        }
    }
}

#[test]
fn public_market_boundary_splits_windows_and_same_phase_recognition_without_resetting_fuel() {
    let mut fixture = Fixture::new();
    let mut recorded = fixture.recorder(true);
    let mut unrecorded = fixture.recorder(false);
    for tick in 1..=5 {
        if tick == 3 {
            enter_market(&mut fixture);
        }
        if tick == 5 {
            fixture
                .state
                .m19
                .as_mut()
                .unwrap()
                .completed
                .push("market_strips".into());
        }
        let mut frame = fixture.frame(tick, GROUND, Some((30 + tick as u16, false)));
        add_strip(&mut frame, 1, false);
        for recorder in [&mut recorded, &mut unrecorded] {
            fixture.observe(recorder, &frame, 0.0);
            if tick >= 2 {
                // The already perceived phase remains present at the boundary:
                // this observer must not impose another acquisition delay.
                recorder.observe_perception(&frame);
            }
            recorder.observe_stall(10.0, &frame.players[0], &fixture.map_info);
        }
    }
    let (metrics, windows) = recorded.finish();
    let (quiet_metrics, quiet_windows) = unrecorded.finish();
    assert_eq!(metrics, quiet_metrics);
    assert!(quiet_windows.is_empty());
    assert_eq!(
        metrics.supported_refuel_ticks, 4,
        "public stages do not reset fuel custody"
    );
    assert_eq!(metrics.paver_phases.len(), 2);
    let teaching = &metrics.paver_phases[0];
    let market = &metrics.paver_phases[1];
    assert_eq!(
        (
            teaching.stage,
            teaching.first_snapshot_tick,
            teaching.recognized_tick
        ),
        (Stage::Teaching, 1, Some(2))
    );
    assert_eq!(
        (
            market.stage,
            market.first_snapshot_tick,
            market.recognized_tick
        ),
        (Stage::Market, 3, Some(3))
    );
    assert_eq!(teaching.owner, market.owner);
    assert_eq!(teaching.started_tick, market.started_tick);
    for event in ["paver_tell", "active_stall"] {
        let selected: Vec<_> = windows
            .iter()
            .filter(|window| window["event"] == event)
            .collect();
        assert_eq!(selected.len(), 2);
        assert_eq!(selected[0]["stage"], "teaching");
        assert_eq!(selected[0]["frames"][0]["tick"], 1);
        assert_eq!(
            selected[0]["frames"].as_array().unwrap().last().unwrap()["tick"],
            2
        );
        assert_eq!(selected[1]["stage"], "market");
        assert_eq!(selected[1]["frames"][0]["tick"], 3);
        assert_eq!(
            selected[1]["frames"].as_array().unwrap().last().unwrap()["tick"],
            5
        );
    }
}

#[test]
fn simultaneous_owner_windows_are_stage_scoped_bounded_and_retry_local() {
    let mut fixture = Fixture::new();
    let initial_objective = fixture.state.m19.as_ref().unwrap().current.clone();
    let mut recorder = fixture.recorder(true);
    for tick in 1..=190 {
        if tick == 5 {
            enter_market(&mut fixture);
        }
        let mut frame = fixture.frame(tick, GROUND, None);
        if tick <= 6 {
            add_strip(&mut frame, 1, false);
            add_second_strip(&mut frame);
        }
        fixture.observe(&mut recorder, &frame, 0.0);
    }
    fixture.state.attempt += 1;
    fixture.state.m19.as_mut().unwrap().completed.clear();
    fixture.state.m19.as_mut().unwrap().current = initial_objective;
    let mut retry = fixture.frame(191, GROUND, None);
    add_strip(&mut retry, 191, false);
    add_second_strip(&mut retry);
    fixture.observe(&mut recorder, &retry, 0.0);
    let (_, windows) = recorder.finish();
    let overlaps: Vec<_> = windows
        .iter()
        .filter(|window| window["event"] == "paver_overlap")
        .collect();
    assert_eq!(overlaps.len(), 3);
    assert_eq!(overlaps[0]["stage"], "teaching");
    assert_eq!(overlaps[0]["frames"].as_array().unwrap().len(), 4);
    assert_eq!(overlaps[1]["stage"], "market");
    let market = overlaps[1]["frames"].as_array().unwrap();
    assert_eq!(market.len(), 160);
    assert_eq!(market.first().unwrap()["tick"], 5);
    assert_eq!(market.last().unwrap()["tick"], 164);
    assert!(market.windows(2).all(|pair| {
        pair[0]["tick"].as_u64().unwrap() + 1 == pair[1]["tick"].as_u64().unwrap()
    }));
    assert_eq!(overlaps[2]["stage"], "teaching");
    assert_eq!(overlaps[2]["attempt"], fixture.state.attempt);
    assert_eq!(overlaps[2]["frames"][0]["tick"], 191);
}

#[test]
fn sequential_or_duplicate_owners_do_not_claim_simultaneous_strips() {
    let mut fixture = Fixture::new();
    enter_market(&mut fixture);
    let mut recorder = fixture.recorder(true);
    for tick in 1..=3 {
        let mut frame = fixture.frame(tick, GROUND, None);
        add_strip(&mut frame, 1, false);
        if tick == 2 {
            add_second_strip(&mut frame);
            frame.paver_strips.remove(0);
        } else if tick == 3 {
            frame.paver_strips.push(frame.paver_strips[0]);
        }
        fixture.observe(&mut recorder, &frame, 0.0);
    }
    let (_, windows) = recorder.finish();
    assert!(windows
        .iter()
        .all(|window| window["event"] != "paver_overlap"));
}
