use super::*;
use crate::protocol::{MapDecoration, MapFace};

fn objective(index: usize) -> MissionObjective {
    MissionObjective {
        id: M11_OBJECTIVE_IDS[index].into(),
        action: MissionObjectiveAction::Arrival {
            region: Region3 {
                min: [-1.0, 0.0, -1.0],
                max: [1.0, 1.0, 1.0],
            },
            feet: [0.0; 3],
        },
    }
}

fn state(index: usize) -> M11ObjectiveState {
    M11ObjectiveState {
        completed: M11_OBJECTIVE_IDS
            .iter()
            .take(index)
            .map(|s| (*s).into())
            .collect(),
        current: if index < 6 {
            Some(objective(index))
        } else {
            Some(MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: UseTarget {
                        decoration: 0,
                        approach: [0.0; 3],
                    },
                },
            })
        },
        challenges: M11ChallengeState {
            counter_boarding_started: (index >= 4).then_some(20),
            signal_due: (index >= 4).then_some(20 + M11_SIGNAL_TICKS),
            bridge_taken_at: (index >= 6).then_some(50),
            ..M11ChallengeState::default()
        },
    }
}

#[test]
fn m11_facts_require_exact_order_action_and_actual_challenge_clocks() {
    for index in 0..=6 {
        state(index).validate(MissionPhase::InProgress, 60).unwrap();
    }
    let mut departed = state(6);
    departed.completed.push("party_departed".into());
    departed.current = None;
    departed.validate(MissionPhase::Departed, 60).unwrap();
    assert!(departed.validate(MissionPhase::InProgress, 60).is_err());
    assert!(
        !departed
            .challenges
            .brief_completed(CampaignDifficulty::Assisted),
        "departure is not gated by optional brief"
    );
    let mut bad = state(3);
    bad.completed.swap(0, 1);
    assert!(bad.validate(MissionPhase::InProgress, 60).is_err());
    bad = state(3);
    bad.current = state(6).current;
    assert!(bad.validate(MissionPhase::InProgress, 60).is_err());
    bad = state(3);
    bad.challenges.records_read = true;
    assert!(bad.validate(MissionPhase::InProgress, 60).is_err());
    bad = state(2);
    bad.challenges.transfer_released = true;
    assert!(bad.validate(MissionPhase::InProgress, 60).is_err());
    state(0).validate(MissionPhase::Briefing, 60).unwrap();
    assert!(state(1).validate(MissionPhase::Briefing, 60).is_err());
    bad = state(0);
    bad.current.as_mut().unwrap().action = MissionObjectiveAction::Shoot {
        solid: 0,
        approach: [0.0; 3],
        aim: [0.0; 3],
    };
    assert!(bad.validate(MissionPhase::InProgress, 60).is_err());
}

#[test]
fn m11_brief_derives_from_one_blast_and_exact_before_signal_boundary() {
    let mut facts = M11ChallengeState {
        transfer_released: true,
        counter_boarding_started: Some(20),
        signal_due: Some(1220),
        bridge_taken_at: Some(1219),
        ..M11ChallengeState::default()
    };
    facts.validate(1220).unwrap();
    assert!(facts.brief_completed(CampaignDifficulty::Assisted));
    assert!(!facts.brief_completed(CampaignDifficulty::Standard));
    facts.counter_boarder_blast_kills = 3;
    assert!(facts.brief_completed(CampaignDifficulty::Standard));
    assert!(facts.brief_completed(CampaignDifficulty::Severe));
    facts.bridge_taken_at = Some(1220);
    assert!(!facts.brief_completed(CampaignDifficulty::Severe));
    facts.validate(1220).unwrap();
    let mut bad = facts.clone();
    bad.counter_boarder_blast_kills = 7;
    assert!(bad.validate(1220).is_err());
    bad = facts.clone();
    bad.signal_due = Some(1219);
    assert!(bad.validate(1220).is_err());
    bad = facts.clone();
    bad.counter_boarding_started = None;
    assert!(bad.validate(1220).is_err());
    bad = facts.clone();
    bad.bridge_taken_at = Some(1221);
    assert!(bad.validate(1220).is_err());
    bad = facts.clone();
    bad.bridge_taken_at = Some(19);
    assert!(bad.validate(1220).is_err());
    bad = M11ChallengeState {
        counter_boarding_started: Some(u64::MAX),
        signal_due: Some(0),
        ..M11ChallengeState::default()
    };
    assert!(bad.validate(u64::MAX).is_err());
    bad = M11ChallengeState {
        counter_boarder_blast_kills: 1,
        ..M11ChallengeState::default()
    };
    assert!(bad.validate(100).is_err());
}

#[test]
fn m11_optional_contract_rejects_forged_fields_and_preserves_unsigned_counts() {
    let valid = serde_json::to_value(state(0)).unwrap();
    let mut bad = valid.clone();
    bad["sorrel_rescued"] = true.into();
    assert!(serde_json::from_value::<M11ObjectiveState>(bad).is_err());
    for value in [
        serde_json::json!(-1),
        serde_json::json!(1.5),
        serde_json::json!("3"),
        serde_json::json!(null),
    ] {
        let mut bad = valid.clone();
        bad["challenges"]["counter_boarder_blast_kills"] = value;
        assert!(serde_json::from_value::<M11ObjectiveState>(bad).is_err());
    }
    let mut bad = valid;
    bad["challenges"]["extra"] = false.into();
    assert!(serde_json::from_value::<M11ObjectiveState>(bad).is_err());
}

#[test]
fn m11_map_binds_distinct_real_panels_and_supported_region_shape() {
    let solid = Solid {
        min_x: -2.0,
        max_x: 2.0,
        min_z: 2.0,
        max_z: 2.5,
        bottom: 0.0,
        top: 3.0,
    };
    let present = MapPresentation {
        ground: crate::protocol::MapSurface::Concrete,
        solids: vec![crate::protocol::MapSurface::Concrete],
        decorations: [
            MapDecorationKind::M11TransferRelease,
            MapDecorationKind::M11RecordsDocument,
            MapDecorationKind::M11SternRelease,
        ]
        .into_iter()
        .map(|kind| MapDecoration {
            solid: 0,
            face: MapFace::North,
            center: [0.0, 0.0],
            size: [0.5, 0.5],
            kind,
        })
        .collect(),
    };
    let target = |decoration| UseTarget {
        decoration,
        approach: [0.0; 3],
    };
    let geometry = M11MapGeometry {
        objectives: (0..6).map(objective).collect(),
        transfer_release: target(0),
        records_document: target(1),
        departure: target(2),
        boarding: Region3 {
            min: [-1.0, 0.0, -1.0],
            max: [1.0, 1.0, 1.0],
        },
        companion_start: [0.0; 3],
        transfer_people: vec![[3.0, 0.0, 0.0], [5.0, 0.0, 0.0], [7.0, 0.0, 0.0]],
    };
    geometry.validate(20.0, &[solid], Some(&present)).unwrap();
    let mut bad = geometry.clone();
    bad.departure.decoration = 0;
    assert!(bad.validate(20.0, &[solid], Some(&present)).is_err());
    bad = geometry.clone();
    bad.transfer_people[1] = bad.transfer_people[0];
    assert!(bad.validate(20.0, &[solid], Some(&present)).is_err());
    bad = geometry.clone();
    bad.objectives[1].id = "wrong".into();
    assert!(bad.validate(20.0, &[solid], Some(&present)).is_err());
    assert!(geometry
        .validate(f32::NAN, &[solid], Some(&present))
        .is_err());
    assert!(geometry.validate(20.0, &[], Some(&present)).is_err());
    assert!(geometry.validate(20.0, &[solid], None).is_err());
}

#[test]
fn m11_native_matches_shared_client_fact_vectors() {
    let vectors: Vec<serde_json::Value> = serde_json::from_str(include_str!(
        "../../../../client/golden/m11_fact_vectors.json"
    ))
    .unwrap();
    assert_eq!(vectors.len(), 32);
    for entry in vectors {
        let phase: MissionPhase = serde_json::from_value(entry["phase"].clone()).unwrap();
        let tick = entry["tick"].as_u64().unwrap();
        let valid = serde_json::from_value::<M11ObjectiveState>(entry["state"].clone())
            .ok()
            .filter(|s| s.validate(phase, tick).is_ok());
        assert_eq!(
            valid.is_some(),
            entry["valid"].as_bool().unwrap(),
            "{}",
            entry["id"]
        );
        if let Some(briefs) = entry.get("briefs") {
            let facts = &valid.unwrap().challenges;
            for (difficulty, expected) in briefs.as_object().unwrap() {
                let difficulty: CampaignDifficulty =
                    serde_json::from_value(difficulty.clone().into()).unwrap();
                assert_eq!(
                    facts.brief_completed(difficulty),
                    expected.as_bool().unwrap(),
                    "{}",
                    entry["id"]
                );
            }
        }
    }
}
