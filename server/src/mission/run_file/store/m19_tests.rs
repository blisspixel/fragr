//! Planned Works joins the current save: completed M18 promotes without an
//! episode refill and an actual departure records its works receipt and the
//! edge into `local_exception`.
use super::*;
use crate::maps::{AuthoredSource, RuntimeMap};
use crate::mission::run_file::{M16Outcome, M17Outcome, M18Outcome, M19Outcome, SavedStep};
use crate::protocol::{MissionReady, Role};
use crate::sim::{GameState, PLAYER_FLOOR_Y};

/// Close one late mission entry with fixed receipts and its pending edge.
fn complete(mut entry: RunDocument) -> RunDocument {
    let SavedStep::MissionEntry {
        mission,
        entry: resources,
    } = &entry.step
    else {
        unreachable!()
    };
    let (mission, resources) = (*mission, resources.clone());
    let next = match mission {
        MissionId::FreedomOfMovement => {
            entry.m16_outcome = Some(M16Outcome {
                ride_started: true,
                green_wave_triggered: true,
                bus_freed: true,
                forecourt_secured: true,
                doors_open: true,
            });
            "peace_without_interruption"
        }
        MissionId::PeaceWithoutInterruption => {
            entry.m17_outcome = Some(M17Outcome {
                approach_breached: true,
                kessel_secured: true,
                core_unsealed: true,
                core_defeated: true,
                voss_captured: true,
            });
            "all_systems_normal"
        }
        MissionId::AllSystemsNormal => {
            entry.m18_outcome = Some(M18Outcome {
                aid_delivered: true,
                square_defended: true,
                collector_neutralized: false,
                overlook_witnessed: true,
                concourse_secured: true,
            });
            "planned_works"
        }
        MissionId::PlannedWorks => {
            entry.m19_outcome = Some(M19Outcome {
                crossing_cleared: true,
                paver_interrupted: true,
                strip_struck: false,
                latch_departed: true,
            });
            "local_exception"
        }
        _ => unreachable!(),
    };
    entry.step = SavedStep::AwaitingMission {
        completed_mission: mission,
        next_mission: next.into(),
        exit: resources,
    };
    entry
}

fn completed_recovery() -> RunDocument {
    let mut source = m15_tests::completed_stadium();
    for mission in [
        MissionId::FreedomOfMovement,
        MissionId::PeaceWithoutInterruption,
        MissionId::AllSystemsNormal,
    ] {
        let next = source
            .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
            .unwrap();
        source = complete(next);
        source
            .validate(m09_tests::HASHES[stage_index(mission)])
            .unwrap();
    }
    source
}

/// A completed Planned Works with its receipt, awaiting Local Exception on
/// the Episode V allowance it entered with.
pub(super) fn completed_works() -> RunDocument {
    let source = completed_recovery();
    let entry = source
        .promote_next(
            MissionId::PlannedWorks,
            m09_tests::HASHES[stage_index(MissionId::PlannedWorks)],
        )
        .unwrap();
    let mut done = complete(entry);
    done.remaining_continues = 2;
    done.validate(m09_tests::HASHES[stage_index(MissionId::PlannedWorks)])
        .unwrap();
    done
}

#[test]
fn completed_recovery_enters_planned_works_on_the_same_allowance() {
    let mut source = completed_recovery();
    source.remaining_continues = 2;
    source.level_start_continues = 2;
    let hash = m09_tests::HASHES[stage_index(MissionId::PlannedWorks)];
    source
        .validate(m09_tests::HASHES[stage_index(MissionId::AllSystemsNormal)])
        .unwrap();
    let entry = source.promote_next(MissionId::PlannedWorks, hash).unwrap();
    assert!(matches!(
        entry.step,
        SavedStep::MissionEntry {
            mission: MissionId::PlannedWorks,
            ..
        }
    ));
    // Same episode: no refill on this edge.
    assert_eq!(
        (entry.remaining_continues, entry.level_start_continues),
        (2, 2)
    );
    assert_eq!(entry.m18_outcome, source.m18_outcome);
    assert!(entry.m19_outcome.is_none());
    entry.validate(hash).unwrap();
    // The entry stage cannot carry a completed works receipt, and the
    // completed recovery cannot skip ahead to any other mission.
    let mut forged = entry.clone();
    forged.m19_outcome = Some(M19Outcome {
        crossing_cleared: true,
        paver_interrupted: false,
        strip_struck: false,
        latch_departed: true,
    });
    assert!(forged.validate(hash).is_err());
    let mut missing = entry.clone();
    missing.m18_outcome = None;
    assert!(missing.validate(hash).is_err());
    for mission in CAMPAIGN_MISSIONS {
        if mission != MissionId::PlannedWorks {
            assert!(source
                .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
                .is_err());
        }
    }
    assert!(entry.promote_next(MissionId::PlannedWorks, hash).is_err());
}

#[test]
fn an_actual_waterworks_departure_saves_the_works_receipt_and_pending_m20() {
    let map = AuthoredSource::Mission(MissionId::PlannedWorks)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let entry = completed_recovery()
        .promote_next(MissionId::PlannedWorks, hash)
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    state.load_campaign_run(&entry).unwrap();
    let id = Uuid::new_v4();
    state.add_player(id, "Works save".into(), Role::Human);
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::PlannedWorks,
            attempt: 1,
        }
    ));
    state.tick(0.05);
    assert_eq!(state.campaign_run_document().unwrap().unwrap(), entry);
    // Reach the trench mouth with every group behind it cleared.
    let g = state.map.m19_geometry().unwrap();
    {
        let run = state.mission.as_mut().unwrap();
        let progress = run.m19.as_mut().unwrap();
        progress.index = 7;
        progress.challenges.crossing_cleared = true;
    }
    let trench = match &g.objectives[7].action {
        crate::protocol::MissionObjectiveAction::Arrival { feet, .. } => *feet,
        _ => unreachable!(),
    };
    let place = |state: &mut GameState, feet: [f32; 3]| {
        let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
        [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
        p.clear_input();
    };
    place(&mut state, trench);
    state.tick(0.05);
    assert!(state.map.m19_geometry().unwrap().gate_open);
    place(&mut state, g.departure.approach);
    let point = g
        .departure
        .point(
            state.map.presentation_ref().unwrap(),
            &state.map.arena().solids,
        )
        .unwrap();
    state.set_action(
        id,
        crate::protocol::Action {
            interact: true,
            look_at: Some(crate::protocol::LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    state.tick(0.05);
    let saved = state.campaign_run_document().unwrap().unwrap();
    assert!(matches!(
        &saved.step,
        SavedStep::AwaitingMission {
            completed_mission: MissionId::PlannedWorks,
            next_mission,
            ..
        } if next_mission == "local_exception"
    ));
    let outcome = saved.m19_outcome.clone().unwrap();
    assert!(outcome.crossing_cleared && outcome.latch_departed);
    assert_eq!(saved.m18_outcome, entry.m18_outcome);
    saved.validate(hash).unwrap();
    // The completed save refuses a missing or contradictory works receipt.
    let mut missing = saved.clone();
    missing.m19_outcome = None;
    assert!(missing.validate(hash).is_err());
    let mut forged = saved.clone();
    forged.m19_outcome.as_mut().unwrap().latch_departed = false;
    assert!(forged.validate(hash).is_err());
    let mut wrong = saved.clone();
    if let SavedStep::AwaitingMission { next_mission, .. } = &mut wrong.step {
        *next_mission = "planned_works".into();
    }
    assert!(wrong.validate(hash).is_err());
    // The completed works enter only the finale.
    for mission in CAMPAIGN_MISSIONS {
        assert_eq!(
            saved
                .promote_next(mission, m09_tests::HASHES[stage_index(mission)])
                .is_ok(),
            mission == MissionId::LocalException,
            "{mission:?}"
        );
    }
}
