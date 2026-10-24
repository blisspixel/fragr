use super::*;
use crate::mission::run_file::{M08Outcome, SavedStep};

pub(super) const HASHES: ContentHashes = [
    [1; 32], [2; 32], [3; 32], [4; 32], [5; 32], [6; 32], [7; 32], [8; 32], [101; 32], [102; 32],
    [103; 32], [104; 32], [105; 32], [106; 32], [107; 32], [108; 32], [109; 32], [110; 32],
    [111; 32],
];

pub(super) fn completed_archive() -> RunDocument {
    let mut document = super::m07_tests::completed_port()
        .promote_next(MissionId::DeclaredGoods, HASHES[6])
        .unwrap();
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::DeclaredGoods,
        next_mission: "custodian_of_record".into(),
        exit: super::m07_tests::exit(true),
    };
    document = document
        .promote_next(MissionId::CustodianOfRecord, HASHES[7])
        .unwrap();
    let mut exit = super::m07_tests::exit(true);
    exit.hp = 39;
    exit.armor = 17;
    exit.equipment.grenades = 2;
    exit.equipment.proximity_mines = 3;
    document.step = SavedStep::AwaitingMission {
        completed_mission: MissionId::CustodianOfRecord,
        next_mission: "passenger_manifest".into(),
        exit,
    };
    document.m08_outcome = Some(M08Outcome {
        custody_released: true,
        recovered_mind_secured: true,
        captives_evacuated: true,
    });
    document.validate(HASHES[7]).unwrap();
    document
}

#[test]
fn m09_entry_round_trips_and_preserves_real_m08_carry() {
    let source = completed_archive()
        .promote_next(MissionId::PassengerManifest, HASHES[8])
        .unwrap();
    let directory = std::env::temp_dir().join(format!("fragr-m09-entry-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, HASHES).unwrap();
    store.save(&source).unwrap();
    assert_eq!(store.load().unwrap().unwrap(), source);
    drop(store);
    let reopened = RunStore::open_with_hashes(&directory, HASHES).unwrap();
    assert_eq!(reopened.load().unwrap().unwrap(), source);
    assert!(source
        .promote_next(MissionId::PassengerManifest, HASHES[8])
        .is_err());
    let SavedStep::MissionEntry { entry, .. } = &source.step else {
        panic!("M09 entry")
    };
    assert_eq!(
        (
            entry.hp,
            entry.armor,
            entry.equipment.grenades,
            entry.equipment.proximity_mines
        ),
        (39, 17, 2, 3)
    );
    drop(reopened);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn pre_m10_documents_refuse_repeater_ownership() {
    let source = completed_archive()
        .promote_next(MissionId::PassengerManifest, HASHES[8])
        .unwrap();
    let initial = RunDocument::new(
        Uuid::new_v4(),
        crate::protocol::CampaignRules::default(),
        HASHES[0],
    );
    for document in [&source, &initial] {
        for selected in [false, true] {
            let mut value = serde_json::to_value(document).unwrap();
            let equipment = &mut value["step"]["entry"]["equipment"];
            equipment["weapons"]
                .as_array_mut()
                .unwrap()
                .push("repeater".into());
            if selected {
                equipment["selected"] = "repeater".into();
            }
            let probe = RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES);
            assert!(
                matches!(probe, RunProbe::Incompatible),
                "a valid shape must refuse unsupported mission ownership"
            );
        }
    }
}

#[test]
fn current_custody_outcomes_require_release_and_refuse_extra_or_missing_facts() {
    let document = completed_archive();
    for custody_released in [false, true] {
        for recovered_mind_secured in [false, true] {
            for captives_evacuated in [false, true] {
                let mut candidate = document.clone();
                candidate.m08_outcome = Some(M08Outcome {
                    custody_released,
                    recovered_mind_secured,
                    captives_evacuated,
                });
                assert_eq!(
                    candidate.validate(HASHES[7]).is_ok(),
                    custody_released || !captives_evacuated
                );
            }
        }
    }
    for malformed in [
        serde_json::Value::Null,
        serde_json::json!({"kind":"historical_unrecorded"}),
        serde_json::json!({"kind":"historical_unrecorded","custody_released":false}),
        serde_json::json!({"kind":"recorded","custody_released":true,"recovered_mind_secured":true,
            "captives_evacuated":true}),
        serde_json::json!({"custody_released":true,"recovered_mind_secured":true}),
        serde_json::json!({"custody_released":true,"recovered_mind_secured":true,
            "captives_evacuated":true,"mind_restored":true}),
    ] {
        let mut value = serde_json::to_value(&document).unwrap();
        value["m08_outcome"] = malformed;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), HASHES),
            RunProbe::Corrupt
        ));
    }
    let mut missing = document.clone();
    missing.m08_outcome = None;
    assert!(missing.validate(HASHES[7]).is_err());
    let mut premature = RunDocument::new(document.id, document.rules, HASHES[0]);
    premature.m08_outcome = document.m08_outcome.clone();
    assert!(premature.validate(HASHES[0]).is_err());
}

#[test]
fn m09_promotion_carries_finite_exit_and_never_refills_episode_two() {
    let source = completed_archive();
    let mut exit = match &source.step {
        SavedStep::AwaitingMission { exit, .. } => exit.clone(),
        _ => panic!("completed archive"),
    };
    exit.equipment.personal_claims.clear();
    let entry = source
        .promote_next(MissionId::PassengerManifest, HASHES[8])
        .unwrap();
    assert_eq!(
        entry.step,
        SavedStep::MissionEntry {
            mission: MissionId::PassengerManifest,
            entry: exit
        }
    );
    assert_eq!(entry.remaining_continues, source.remaining_continues);
    assert_eq!(entry.level_start_continues, source.remaining_continues);
    assert_eq!(entry.m08_outcome, source.m08_outcome);
    assert_eq!(entry.m03_outcome, source.m03_outcome);
    assert_eq!(entry.m04_outcome, source.m04_outcome);
    assert_eq!(entry.m05_outcome, source.m05_outcome);
    assert_eq!(entry.m06_outcome, source.m06_outcome);
    assert!(source
        .promote_next(MissionId::PortOfEntry, HASHES[5])
        .is_err());
    assert!(matches!(
        RunStore::inspect_bytes(&serde_json::to_vec(&entry).unwrap(), HASHES),
        RunProbe::Compatible(_)
    ));
}

#[test]
fn m09_low_resource_carry_stays_safe_until_real_loading_crossing_after_tack_pickup() {
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::{Action, MissionReady, Role, WeaponType};
    use crate::sim::GameState;
    let map = AuthoredSource::Mission(MissionId::PassengerManifest)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let saved = completed_archive()
        .promote_next(MissionId::PassengerManifest, hash)
        .unwrap();
    let anchor = match &saved.step {
        SavedStep::MissionEntry { entry, .. } => entry.clone(),
        _ => panic!("entry"),
    };
    assert_eq!((anchor.hp, anchor.armor), (39, 17));
    let owner = Uuid::from_u128(9009);
    let mut game = GameState::with_authored_map(map);
    game.load_campaign_run(&saved).unwrap();
    game.add_player(owner, "Visitor".into(), Role::Human);
    for ready in [false, true] {
        if ready {
            assert!(game.acknowledge_mission(
                owner,
                MissionReady {
                    id: MissionId::PassengerManifest,
                    attempt: 1,
                }
            ));
        }
        for _ in 0..120 {
            game.tick(0.05);
        }
        let player = game.players.iter().find(|p| p.id == owner).unwrap();
        assert_eq!(
            crate::mission::run_file::SavedEntry::from_player(player).unwrap(),
            anchor
        );
        assert!(
            !game.encounters.is_awake(0),
            "story/readiness cannot start loading combat at the mission entry"
        );
    }
    game.set_action(
        owner,
        Action {
            forward: true,
            yaw: Some(std::f32::consts::FRAC_PI_2),
            ..Action::default()
        },
    );
    let mut crossed = false;
    for _ in 0..80 {
        game.tick(0.05);
        let player = game.players.iter().find(|p| p.id == owner).unwrap();
        if game.encounters.is_awake(0) {
            assert!(
                player.inventory.owns(WeaponType::Tack),
                "ordinary Tack pickup precedes deliberate encounter entry"
            );
            assert_eq!(player.inventory.grenades(), 2);
            assert_eq!(player.inventory.mines(), 3);
            assert_eq!(
                game.players
                    .iter()
                    .filter(|p| p.is_campaign_enemy())
                    .count(),
                5
            );
            crossed = true;
            break;
        }
    }
    assert!(
        crossed,
        "ordinary movement must activate the complete loading roster"
    );
}

#[test]
fn m09_carried_custody_survives_actual_retry_and_newer_inventory_revisions() {
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::{Action, MissionContinue, MissionReady, Role};
    use crate::sim::GameState;
    let map = AuthoredSource::Mission(MissionId::PassengerManifest)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let source = completed_archive();
    let saved = source
        .promote_next(MissionId::PassengerManifest, hash)
        .unwrap();
    let anchor = match &saved.step {
        SavedStep::MissionEntry { entry, .. } => entry.clone(),
        _ => panic!("entry"),
    };
    let mut game = GameState::with_authored_map(map.clone());
    game.load_campaign_run(&saved).unwrap();
    let owner = Uuid::from_u128(9009);
    game.add_player(owner, "Visitor".into(), Role::Human);
    assert!(game.acknowledge_mission(
        owner,
        MissionReady {
            id: MissionId::PassengerManifest,
            attempt: 1
        }
    ));
    let original = game
        .players
        .iter()
        .find(|p| p.id == owner)
        .unwrap()
        .inventory
        .revision();
    game.set_action(
        owner,
        Action {
            seq: Some(11),
            place_mine: true,
            ..Action::default()
        },
    );
    game.tick(0.05);
    assert_eq!(game.snapshot().mines.len(), 1);
    let player = game.players.iter_mut().find(|p| p.id == owner).unwrap();
    assert_eq!(player.inventory.mines(), 2);
    assert_eq!(player.inventory.grenades(), 2);
    player.hp = 0;
    game.update_campaign_run();
    let pending = game.campaign_run_document().unwrap().unwrap();
    assert_eq!(pending.m08_outcome, source.m08_outcome);
    assert!(matches!(&pending.step,SavedStep::PendingContinue{entry,..} if *entry==anchor));
    let mut reopened = GameState::with_authored_map(map);
    reopened.load_campaign_run(&pending).unwrap();
    reopened.add_player(owner, "Visitor".into(), Role::Human);
    for state in [&mut reopened, &mut game] {
        assert!(state.continue_mission(
            owner,
            MissionContinue {
                id: MissionId::PassengerManifest,
                run_id: saved.id,
                attempt: 1
            }
        ));
        assert_eq!(
            state.mission_state().unwrap().m09.unwrap().carried_archive,
            source.m08_outcome
        );
        let player = state.players.iter().find(|p| p.id == owner).unwrap();
        assert_eq!(
            crate::mission::run_file::SavedEntry::from_player(player).unwrap(),
            anchor
        );
        assert!(state.snapshot().mines.is_empty());
    }
    let player = game.players.iter().find(|p| p.id == owner).unwrap();
    assert!(player.inventory.revision() > original);
    assert_eq!(player.last_input_seq, Some(11));
    let after = game.campaign_run_document().unwrap().unwrap();
    assert_eq!(after.m08_outcome, saved.m08_outcome);
    assert_eq!(after.remaining_continues, saved.remaining_continues - 1);
    let directory = std::env::temp_dir().join(format!("fragr-m09-carry-{}", Uuid::new_v4()));
    let store = RunStore::open_with_hashes(&directory, [hash; CAMPAIGN_STAGES]).unwrap();
    store.save(&after).unwrap();
    assert_eq!(store.load().unwrap().unwrap(), after);
    drop(store);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn m09_capture_route_preflights_real_held_and_released_contacts_for_all_four_casts() {
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::{Action, LookAt, MissionPhase, MissionReady, Role};
    use crate::sim::{GameState, PLAYER_FLOOR_Y};
    // This is a contact and gate preflight, not combat acceptance. Each
    // currently placed guard is explicitly disabled as a seeded fixture.
    fn tick_without_guards(game: &mut GameState) {
        let enemies: Vec<_> = game
            .players
            .iter()
            .filter(|p| p.is_campaign_enemy() && p.hp > 0)
            .map(|p| (p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z]))
            .collect();
        for (id, feet) in enemies {
            game.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
            game.encounters.hit(id, feet, game.tick, true);
        }
        game.tick(0.05);
    }
    fn walk(game: &mut GameState, owner: Uuid, goal: [f32; 3], context: &str) {
        for _ in 0..300 {
            let p = game.players.iter().find(|p| p.id == owner).unwrap();
            let dx = goal[0] - p.x;
            let dz = goal[2] - p.z;
            if dx.hypot(dz) < 0.3 && (p.y - PLAYER_FLOOR_Y - goal[1]).abs() < 0.03 {
                game.set_action(owner, Action::default());
                tick_without_guards(game);
                return;
            }
            game.set_action(
                owner,
                Action {
                    forward: true,
                    yaw: Some(dz.atan2(dx)),
                    ..Action::default()
                },
            );
            tick_without_guards(game);
        }
        let p = game.players.iter().find(|p| p.id == owner).unwrap();
        panic!(
            "{context}: actual feet {:?} did not reach {goal:?}, actual crew {:?}",
            [p.x, p.y - PLAYER_FLOOR_Y, p.z],
            game.mission_state().unwrap().m09.unwrap().crew
        );
    }
    let map = AuthoredSource::Mission(MissionId::PassengerManifest)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    let qa: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../../client/qa/m09_passenger_manifest.json"
    ))
    .unwrap();
    for edda in [false, true] {
        for splice in [false, true] {
            for boarding_count in [0, 1, 2] {
                let mut source = completed_archive();
                if !edda {
                    source
                        .m04_outcome
                        .as_mut()
                        .unwrap()
                        .rescued_patients
                        .clear();
                }
                if !splice {
                    source
                        .m05_outcome
                        .as_mut()
                        .unwrap()
                        .evacuated_workers
                        .clear();
                }
                let saved = source
                    .promote_next(MissionId::PassengerManifest, hash)
                    .unwrap();
                let mut game = GameState::with_authored_map(map.clone());
                game.load_campaign_run(&saved).unwrap();
                let owner = Uuid::from_u128(9009);
                game.add_player(owner, "Visitor".into(), Role::Human);
                assert!(game.acknowledge_mission(
                    owner,
                    MissionReady {
                        id: MissionId::PassengerManifest,
                        attempt: 1
                    }
                ));
                assert_eq!(
                    game.mission_state().unwrap().m09.unwrap().crew.len(),
                    3 + usize::from(edda) + usize::from(splice)
                );
                for state in qa["states"].as_array().unwrap() {
                    let context = format!("{} edda={edda} splice={splice}", state["name"]);
                    for route in [state.get("walk_to"), state["combat"].get("search_route")]
                        .into_iter()
                        .flatten()
                    {
                        for goal in serde_json::from_value::<Vec<[f32; 3]>>(route.clone()).unwrap()
                        {
                            walk(&mut game, owner, goal, &context);
                        }
                    }
                    if let Some(control) = state["interact"].as_str() {
                        if control != "crew_freed" && boarding_count > 0 {
                            // This independent branch proves optional crew can
                            // finish after all authored holds lift. Capture
                            // either a naturally partial or fully boarded roster;
                            // the zero branch proves there is no NPC wait gate.
                            game.set_action(owner, Action::default());
                            for _ in 0..4000 {
                                let crew = game.mission_state().unwrap().m09.unwrap().crew;
                                if (boarding_count == 1 && crew.iter().any(|c| c.aboard))
                                    || crew.iter().all(|c| c.aboard)
                                {
                                    break;
                                }
                                tick_without_guards(&mut game);
                            }
                            let crew = game.mission_state().unwrap().m09.unwrap().crew;
                            assert!(
                                if boarding_count == 1 {
                                    crew.iter().any(|c| c.aboard) && crew.iter().any(|c| !c.aboard)
                                } else {
                                    crew.iter().all(|c| c.aboard)
                                },
                                "optional crew did not finish: {crew:?}"
                            );
                        }
                        let g = game.map.m09_geometry().unwrap();
                        let target = if control == "crew_freed" {
                            g.crew_release
                        } else {
                            g.departure
                        };
                        let point = target
                            .point(
                                game.map.presentation_ref().unwrap(),
                                &game.current_arena().solids,
                            )
                            .unwrap();
                        game.set_action(owner, Action::default());
                        tick_without_guards(&mut game);
                        game.set_action(
                            owner,
                            Action {
                                interact: true,
                                look_at: Some(LookAt {
                                    x: Some(point[0]),
                                    y: Some(point[1]),
                                    z: Some(point[2]),
                                    player_id: None,
                                }),
                                ..Action::default()
                            },
                        );
                        tick_without_guards(&mut game);
                    }
                    if let Some(expected) = state.get("expect_m09_completed") {
                        assert_eq!(
                            game.mission_state().unwrap().m09.unwrap().completed,
                            serde_json::from_value::<Vec<String>>(expected.clone()).unwrap(),
                            "{context}"
                        );
                    }
                }
                assert_eq!(game.mission_state().unwrap().phase, MissionPhase::Departed);
                let crew = game.mission_state().unwrap().m09.unwrap().crew;
                if boarding_count == 0 {
                    assert!(crew.iter().all(|c| !c.aboard));
                } else if boarding_count == 1 {
                    assert!(crew.iter().any(|c| c.aboard) && crew.iter().any(|c| !c.aboard));
                }
                let boarding = game.map.m09_geometry().unwrap().boarding;
                let document = game.campaign_run_document().unwrap().unwrap();
                let expected = crate::mission::run_file::M09Outcome {
                    released_crew: crew.iter().map(|c| c.id.clone()).collect(),
                    aboard_at_departure: crew
                        .iter()
                        .filter(|c| boarding.contains(c.feet))
                        .map(|c| c.id.clone())
                        .collect(),
                };
                assert_eq!(document.m09_outcome, Some(expected));
                let directory = std::env::temp_dir()
                    .join(format!("fragr-m09-actual-receipt-{}", Uuid::new_v4()));
                let store =
                    RunStore::open_with_hashes(&directory, [hash; CAMPAIGN_STAGES]).unwrap();
                store.save(&document).unwrap();
                assert_eq!(store.load().unwrap().unwrap(), document);
                drop(store);
                let reopened =
                    RunStore::open_with_hashes(&directory, [hash; CAMPAIGN_STAGES]).unwrap();
                assert_eq!(reopened.load().unwrap().unwrap(), document);
                drop(reopened);
                fs::remove_dir_all(directory).unwrap();
                // A stale later body/presenter observation cannot rewrite the
                // immutable actual departure receipt or finite player exit.
                for crew in &mut game.mission.as_mut().unwrap().m09.as_mut().unwrap().crew {
                    crew.feet = [0.0; 3];
                    crew.aboard = !crew.aboard;
                }
                for _ in 0..3 {
                    game.tick(0.05);
                }
                assert_eq!(game.campaign_run_document().unwrap().unwrap(), document);
                let receipt = game
                    .mission
                    .as_mut()
                    .unwrap()
                    .m09
                    .as_mut()
                    .unwrap()
                    .departure_outcome
                    .take();
                assert!(
                    game.campaign_run_document().is_err(),
                    "a fabricated native completion without its actual receipt must refuse"
                );
                game.mission
                    .as_mut()
                    .unwrap()
                    .m09
                    .as_mut()
                    .unwrap()
                    .departure_outcome = receipt;
            }
        }
    }
}

#[test]
fn m09_cast_uses_authored_clinic_condition_and_actual_splice_evacuation_only() {
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::{MissionContinue, MissionReady, Role};
    use crate::sim::GameState;
    let map = AuthoredSource::Mission(MissionId::PassengerManifest)
        .load()
        .unwrap();
    let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
    for rescued in [false, true] {
        for evacuated in [false, true] {
            let mut source = completed_archive();
            let clinic = source.m04_outcome.as_mut().unwrap();
            clinic.rescued_patients = if rescued {
                vec!["edda_team_a".into()]
            } else {
                vec![]
            };
            let workshop = source.m05_outcome.as_mut().unwrap();
            workshop.released_workers = vec![
                "splice".into(),
                "workshop_agent_a".into(),
                "workshop_agent_b".into(),
            ];
            workshop.evacuated_workers = if evacuated {
                vec!["splice".into()]
            } else {
                vec![]
            };
            let entry = source
                .promote_next(MissionId::PassengerManifest, hash)
                .unwrap();
            let owner = Uuid::from_u128(9009);
            let mut game = GameState::with_authored_map(map.clone());
            game.load_campaign_run(&entry).unwrap();
            game.add_player(owner, "Visitor".into(), Role::Human);
            assert!(game.acknowledge_mission(
                owner,
                MissionReady {
                    id: MissionId::PassengerManifest,
                    attempt: 1
                }
            ));
            let mut expected: Vec<String> = ["tern", "berth_crew_a", "berth_crew_b"]
                .map(str::to_owned)
                .to_vec();
            if rescued {
                expected.push("edda".into());
            }
            if evacuated {
                expected.push("splice".into());
            }
            let first = game.mission_state().unwrap();
            first.validate(game.tick).unwrap();
            assert_eq!(
                first
                    .m09
                    .unwrap()
                    .crew
                    .iter()
                    .map(|c| c.id.clone())
                    .collect::<Vec<_>>(),
                expected
            );
            game.players.iter_mut().find(|p| p.id == owner).unwrap().hp = 0;
            game.update_campaign_run();
            assert!(game.continue_mission(
                owner,
                MissionContinue {
                    id: MissionId::PassengerManifest,
                    run_id: entry.id,
                    attempt: 1
                }
            ));
            assert_eq!(
                game.mission_state()
                    .unwrap()
                    .m09
                    .unwrap()
                    .crew
                    .iter()
                    .map(|c| c.id.clone())
                    .collect::<Vec<_>>(),
                expected
            );
            let after = game.campaign_run_document().unwrap().unwrap();
            assert_eq!(
                after.m04_outcome, source.m04_outcome,
                "appearance adds no individual survival fact"
            );
            assert_eq!(
                after.m05_outcome, source.m05_outcome,
                "release alone is not evacuation"
            );
        }
    }
}
