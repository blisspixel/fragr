use super::*;
use crate::mission::run_file::{M09Outcome, SavedStep};
use crate::protocol::{CampaignRunStatus, M10Transit, MissionContinue, MissionReady, Role};
use crate::sim::{GameState, PLAYER_FLOOR_Y};

#[test]
fn m10_real_promotion_completes_only_released_crew_and_retry_keeps_its_entry() {
    let map = crate::maps::AuthoredSource::Mission(MissionId::CommonCarrier)
        .load()
        .unwrap();
    for (edda, splice, known) in [
        (false, false, true),
        (true, false, true),
        (false, true, true),
        (true, true, true),
        (true, true, false),
    ] {
        let mut before = m09_receipt_tests::completed_berth(edda, splice);
        before.remaining_continues = 1;
        if !known {
            before.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
        }
        let receipt = before.m09_outcome.clone();
        let SavedStep::AwaitingMission { exit, .. } = &before.step else {
            panic!("berth exit");
        };
        let mut entry = exit.clone();
        entry.equipment.personal_claims.clear();
        let promoted = before
            .promote_next(
                MissionId::CommonCarrier,
                crate::maps::RuntimeMap::Authored(map.clone())
                    .content_sha256()
                    .unwrap(),
            )
            .unwrap();
        assert_eq!(promoted.remaining_continues, 3);
        assert_eq!(promoted.level_start_continues, 3);
        assert_eq!(promoted.m09_outcome, receipt);
        match (&receipt, &promoted.m10_transit) {
            (
                Some(M09Outcome::Recorded {
                    released_crew,
                    aboard_at_departure,
                }),
                Some(M10Transit::Recorded { arrived_crew }),
            ) => {
                assert!(
                    aboard_at_departure.is_empty(),
                    "the true old zero-aboard fact stays empty"
                );
                assert_eq!(arrived_crew, released_crew);
            }
            (
                Some(M09Outcome::HistoricalUnrecorded {}),
                Some(M10Transit::HistoricalUnrecorded {}),
            ) => {}
            _ => panic!("unknown history or actual release was fabricated"),
        }
        assert_eq!(
            promoted.step,
            SavedStep::MissionEntry {
                mission: MissionId::CommonCarrier,
                entry: entry.clone()
            }
        );
        assert!(promoted
            .promote_next(
                MissionId::CommonCarrier,
                crate::maps::RuntimeMap::Authored(map.clone())
                    .content_sha256()
                    .unwrap()
            )
            .is_err());
        let mut state = GameState::with_authored_map(map.clone());
        state.load_campaign_run(&promoted).unwrap();
        let id = Uuid::new_v4();
        state.add_player(id, "Ship retry".into(), Role::Human);
        state.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::CommonCarrier,
                attempt: 1,
            },
        );
        let facts = state.mission_state().unwrap();
        facts.validate(state.tick).unwrap();
        let ship = facts.m10.as_ref().unwrap();
        assert_eq!(
            ship.pilot,
            crate::maps::RuntimeMap::Authored(map.clone())
                .m10_geometry()
                .unwrap()
                .pilot,
            "current Tern appears independently of history"
        );
        assert_eq!(
            ship.passengers.iter().any(|p| p.id == "edda"),
            known && edda
        );
        assert_eq!(
            ship.passengers.iter().any(|p| p.id == "splice"),
            known && splice
        );
        assert_eq!(
            ship.passengers.len(),
            if known {
                2 + usize::from(edda) + usize::from(splice)
            } else {
                0
            }
        );
        for _ in 0..40 {
            state.tick(0.05);
            state.take_events();
        }
        let player = state.players.iter().find(|p| p.id == id).unwrap();
        assert_eq!(
            (player.hp, player.armor),
            (entry.hp, entry.armor),
            "readiness cannot wake distant boarders"
        );
        assert_eq!(state.campaign_run_document().unwrap().unwrap(), promoted);
        let old_tick = state.tick;
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.hp = 0;
        player.respawn_timer = None;
        state.tick(0.05);
        let dead = state.mission_state().unwrap();
        assert_eq!(dead.run.unwrap().status, CampaignRunStatus::Continue);
        let request = MissionContinue {
            id: MissionId::CommonCarrier,
            run_id: promoted.id,
            attempt: 1,
        };
        assert!(state.continue_mission(id, request));
        assert!(!state.continue_mission(id, request));
        let retry = state.campaign_run_document().unwrap().unwrap();
        assert_eq!(retry.remaining_continues, 2);
        assert_eq!(retry.level_start_continues, 3);
        assert_eq!(retry.step, promoted.step);
        assert_eq!(retry.m09_outcome, promoted.m09_outcome);
        assert_eq!(retry.m10_transit, promoted.m10_transit);
        assert!(state.tick > old_tick);
        let player = state.players.iter().find(|p| p.id == id).unwrap();
        assert!((player.y - PLAYER_FLOOR_Y - 4.8).abs() < 0.01);
    }
}

#[test]
fn m10_locked_v12_upgrade_preserves_bytes_then_commits_distinct_transit_once() {
    for known in [false, true] {
        let mut source = m09_receipt_tests::completed_berth(true, true);
        source.remaining_continues = 1;
        if !known {
            source.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
        }
        let mut value = serde_json::to_value(&source).unwrap();
        value["version"] = 12.into();
        value["rules"]["revision"] = (3).into();
        super::super::omit_historical_rockets(&mut value);
        let mut bytes = serde_json::to_vec_pretty(&value).unwrap();
        bytes.extend_from_slice(b"\n \n");
        let directory = std::env::temp_dir().join(format!("fragr-m10-transit-{}", Uuid::new_v4()));
        let store = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
        fs::write(directory.join(RUN_NAME), &bytes).unwrap();
        let loaded = store.load().unwrap().unwrap();
        assert_eq!(loaded, source);
        assert!(store.needs_upgrade().unwrap());
        let promoted = loaded
            .promote_next(MissionId::CommonCarrier, m09_tests::HASHES[9])
            .unwrap();
        assert!(store
            .archive_and_save_before_replace(&loaded, &promoted, |_| Err(io::Error::other(
                "interrupted transition"
            )))
            .is_err());
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
        let archive = store.archive_and_save(&loaded, &promoted).unwrap();
        assert_eq!(fs::read(archive).unwrap(), bytes);
        assert_eq!(store.load().unwrap().unwrap(), promoted);
        assert!(!store.needs_upgrade().unwrap());
        drop(store);
        let reopened = RunStore::open_with_hashes(&directory, m09_tests::HASHES).unwrap();
        assert_eq!(reopened.load().unwrap().unwrap(), promoted);
        assert!(
            reopened.archive_and_save(&loaded, &promoted).is_err(),
            "stale promotion cannot duplicate arrival/refill"
        );
        drop(reopened);
        fs::remove_dir_all(directory).unwrap();
    }
}

#[test]
fn m10_transit_refuses_forged_current_and_historical_ownership_or_arrivals() {
    let before = m09_receipt_tests::completed_berth(true, true);
    let promoted = before
        .promote_next(MissionId::CommonCarrier, m09_tests::HASHES[9])
        .unwrap();
    for transit in [
        serde_json::json!({"kind":"recorded","arrived_crew":["tern","berth_crew_a","berth_crew_b"]}),
        serde_json::json!({"kind":"historical_unrecorded"}),
        serde_json::json!({"kind":"recorded","arrived_crew":["tern","berth_crew_a","berth_crew_b","edda","edda"]}),
    ] {
        let mut value = serde_json::to_value(&promoted).unwrap();
        value["m10_transit"] = transit;
        assert!(!matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), m09_tests::HASHES),
            RunProbe::Compatible(_)
        ));
    }
    for version in [10, 11, 12] {
        let mut value = serde_json::to_value(&promoted).unwrap();
        value["version"] = version.into();
        value["rules"]["revision"] = (if version <= 4 {
            2
        } else if version < super::super::RUN_FILE_VERSION {
            3
        } else {
            crate::protocol::CAMPAIGN_RULES_REVISION
        })
        .into();
        value.as_object_mut().unwrap().remove("m10_transit");
        if version < 12 {
            value.as_object_mut().unwrap().remove("m09_outcome");
        }
        assert!(
            !matches!(
                RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), m09_tests::HASHES),
                RunProbe::Compatible(_)
            ),
            "historical M10 must refuse"
        );
        let mut value = serde_json::to_value(&before).unwrap();
        value["version"] = version.into();
        value["rules"]["revision"] = (if version <= 4 {
            2
        } else if version < super::super::RUN_FILE_VERSION {
            3
        } else {
            crate::protocol::CAMPAIGN_RULES_REVISION
        })
        .into();
        if version < 12 {
            value.as_object_mut().unwrap().remove("m09_outcome");
        }
        value["m10_transit"] = serde_json::Value::Null;
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), m09_tests::HASHES),
            RunProbe::Corrupt
        ));
    }
}

#[test]
fn m10_ready_session_keeps_future_guards_out_of_actual_crew_and_medkit_paths() {
    use crate::protocol::{Action, AmmoCount, AmmoPool, WeaponType};
    use crate::session::GameSession;
    let source = crate::maps::AuthoredSource::Mission(MissionId::CommonCarrier)
        .load()
        .unwrap();
    for (edda, splice, known) in [
        (false, false, true),
        (true, false, true),
        (false, true, true),
        (true, true, true),
        (true, true, false),
    ] {
        let mut before = m09_receipt_tests::completed_berth(edda, splice);
        if !known {
            before.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
        }
        let SavedStep::AwaitingMission { exit, .. } = &mut before.step else {
            panic!("actual departure fixture");
        };
        // Exact representative carry used by the retained ordinary tours.
        exit.equipment.weapons = vec![
            WeaponType::Fists,
            WeaponType::Flechette,
            WeaponType::Scatter,
            WeaponType::Sniper,
        ];
        exit.equipment.ammo = vec![
            AmmoCount {
                pool: AmmoPool::Bullets,
                rounds: 76,
            },
            AmmoCount {
                pool: AmmoPool::Shells,
                rounds: 32,
            },
            AmmoCount {
                pool: AmmoPool::Cells,
                rounds: 1,
            },
            AmmoCount {
                pool: AmmoPool::Rockets,
                rounds: 0,
            },
        ];
        let promoted = before
            .promote_next(
                MissionId::CommonCarrier,
                crate::maps::RuntimeMap::Authored(source.clone())
                    .content_sha256()
                    .unwrap(),
            )
            .unwrap();
        let mut session = GameSession::with_authored_map(source.clone());
        session.state.seed(42);
        session.state.load_campaign_run(&promoted).unwrap();
        let id = Uuid::from_u128(1010);
        session
            .state
            .add_player(id, "Actual cabin walker".into(), Role::Human);
        for _ in 0..40 {
            session.tick_messages(0.05);
        }
        assert!(session.state.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::CommonCarrier,
                attempt: 1,
            }
        ));
        for _ in 0..40 {
            session.tick_messages(0.05);
        }
        let facts = session.state.mission_state().unwrap().m10.unwrap();
        assert_eq!(
            facts.passengers.len(),
            if known {
                2 + usize::from(edda) + usize::from(splice)
            } else {
                0
            }
        );
        assert_eq!(
            facts.passengers.iter().any(|p| p.id == "edda"),
            known && edda
        );
        assert_eq!(
            facts.passengers.iter().any(|p| p.id == "splice"),
            known && splice
        );
        let initial_equipment = session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .inventory
            .saved_equipment(WeaponType::Sniper)
            .unwrap();
        for target in [
            [0.0, 4.8, -12.1],
            [3.5, 4.8, -12.1],
            [3.5, 4.8, -14.0],
            [5.5, 4.8, -14.0],
            [3.5, 4.8, -14.0],
            [3.5, 4.8, -12.1],
            [0.0, 4.8, -12.1],
            [0.0, 4.8, -15.0],
            [0.0, 4.8, -17.2],
            [-4.45, 4.8, -17.2],
            [-4.45, 4.8, -14.5],
            [-4.45, 3.4, -4.5],
            [-6.55, 3.4, -4.5],
            [-6.55, 2.0, -14.5],
            [-6.55, 3.4, -4.5],
            [-4.45, 3.4, -4.5],
            [-4.45, 4.8, -14.5],
            [-4.45, 4.8, -17.2],
            [0.0, 4.8, -17.2],
            [0.0, 4.8, -12.1],
            [0.0, 4.8, -17.2],
            [-4.45, 4.8, -17.2],
            [-4.45, 4.8, -14.5],
            [-6.55, 4.8, -14.5],
            [-6.55, 6.2, -4.5],
            [-4.45, 6.2, -4.5],
            [-4.45, 7.6, -14.5],
            [-2.5, 7.6, -14.5],
            [-4.0, 7.6, -14.5],
            [-2.5, 7.6, -14.5],
            [-2.5, 7.6, 14.0],
            [0.0, 7.6, 14.0],
            [6.65, 7.6, 14.5],
            [0.0, 7.6, 14.0],
            [6.65, 7.6, 14.5],
            [6.65, 6.2, 4.5],
            [4.55, 6.2, 4.5],
            [4.55, 4.8, 14.5],
            [0.0, 4.8, 14.0],
            [4.55, 4.8, 14.5],
            [4.55, 6.2, 4.5],
            [6.65, 6.2, 4.5],
            [6.65, 7.6, 14.5],
            [0.0, 7.6, 14.0],
            [-2.5, 7.6, 14.0],
            [-2.5, 7.6, -14.5],
            [-4.0, 7.6, -14.5],
            [-4.45, 7.6, -14.5],
            [-4.45, 6.2, -4.5],
            [-6.55, 6.2, -4.5],
            [-6.55, 4.8, -14.5],
            [-4.45, 4.8, -14.5],
            [-4.45, 4.8, -17.2],
            [0.0, 4.8, -17.2],
            [0.0, 4.8, -15.0],
        ] {
            let mut arrived = false;
            for _ in 0..300 {
                let player = session.state.players.iter().find(|p| p.id == id).unwrap();
                let here = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
                if (here[0] - target[0]).hypot(here[2] - target[2]) <= 0.3
                    && (here[1] - target[1]).abs() <= 0.03
                {
                    arrived = true;
                    break;
                }
                // The same direct ordinary walk as QA, without a controller
                // detour, teleports, disabled guards or collision exceptions.
                session.state.set_action(
                    id,
                    Action {
                        forward: true,
                        yaw: Some((target[2] - here[2]).atan2(target[0] - here[0])),
                        ..Action::default()
                    },
                );
                session.tick_messages(0.05);
                let guards: Vec<_> = session
                    .state
                    .players
                    .iter()
                    .filter(|p| p.is_campaign_enemy())
                    .collect();
                assert_eq!(guards.len(), 4, "only the original first group is placed");
                assert!(guards
                    .iter()
                    .all(|p| p.hp > 0 && !session.state.encounters.is_active_enemy(p.id)));
            }
            let player = session.state.players.iter().find(|p| p.id == id).unwrap();
            assert!(
                arrived,
                "edda={edda} splice={splice} known={known} target={target:?} stalled at {:?}",
                [player.x, player.y - PLAYER_FLOOR_Y, player.z]
            );
            session.state.set_action(id, Action::default());
        }
        let player = session.state.players.iter().find(|p| p.id == id).unwrap();
        assert_eq!(
            (player.hp, player.armor),
            (89, 67),
            "actual finite cabin medkit and crew armor, no damage or invented grant"
        );
        assert_eq!(
            player
                .inventory
                .saved_equipment(WeaponType::Sniper)
                .unwrap(),
            initial_equipment
        );
        assert!(
            !session
                .state
                .pickups
                .iter()
                .find(|p| p.id == "passenger_medical")
                .unwrap()
                .available
        );
        assert!(
            !session
                .state
                .pickups
                .iter()
                .find(|p| p.id == "crew_armor")
                .unwrap()
                .available,
            "the ordinary upper aisle claims the real finite armor"
        );
        for _ in 0..400 {
            session.tick_messages(0.05);
        }
        assert!(
            !session
                .state
                .pickups
                .iter()
                .find(|p| p.id == "passenger_medical")
                .unwrap()
                .available
        );
        assert_eq!(
            session
                .state
                .campaign_run_document()
                .unwrap()
                .unwrap()
                .m10_transit,
            promoted.m10_transit
        );
        assert!(session
            .state
            .mission_state()
            .unwrap()
            .m10
            .unwrap()
            .completed
            .is_empty());
    }
}

#[test]
fn m10_live_crew_contacts_preserve_both_stairs_and_actual_finite_supply_routes() {
    use crate::navigation::{NavigationGoal, Navigator};
    use crate::protocol::Action;
    let source = crate::maps::AuthoredSource::Mission(MissionId::CommonCarrier)
        .load()
        .unwrap();
    assert_eq!(
        crate::maps::RuntimeMap::Authored(source.clone())
            .encounters()
            .iter()
            .map(|g| g.enemies.len())
            .sum::<usize>(),
        17
    );
    // Structural/contact proof only, using the production map and roster.
    // Disable placed guards as an explicit fixture, never combat acceptance.
    fn tick_without_guards(state: &mut GameState) {
        let guards: Vec<_> = state
            .players
            .iter()
            .filter(|p| p.is_campaign_enemy() && p.hp > 0)
            .map(|p| (p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z]))
            .collect();
        for (id, feet) in guards {
            state.players.iter_mut().find(|p| p.id == id).unwrap().hp = 0;
            state.encounters.hit(id, feet, state.tick, true);
        }
        state.tick(0.05);
    }
    for (edda, splice, known) in [
        (false, false, true),
        (true, false, true),
        (false, true, true),
        (true, true, true),
        (true, true, false),
    ] {
        let mut before = m09_receipt_tests::completed_berth(edda, splice);
        if !known {
            before.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
        }
        let promoted = before
            .promote_next(
                MissionId::CommonCarrier,
                crate::maps::RuntimeMap::Authored(source.clone())
                    .content_sha256()
                    .unwrap(),
            )
            .unwrap();
        let mut state = GameState::with_authored_map(source.clone());
        state.load_campaign_run(&promoted).unwrap();
        let id = Uuid::new_v4();
        state.add_player(id, "Crew contact route".into(), Role::Human);
        assert!(state.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::CommonCarrier,
                attempt: 1
            }
        ));
        let mut contacts = Vec::new();
        state.append_civilian_contacts(&mut contacts);
        assert_eq!(
            contacts.len(),
            1 + if known {
                2 + usize::from(edda) + usize::from(splice)
            } else {
                0
            }
        );
        assert!(contacts.iter().any(|b| b.key == "m10/tern"));
        let mut navigator = Navigator::default();
        for target in [
            [0.0, 4.8, -12.1],
            [3.5, 4.8, -12.1],
            [3.5, 4.8, -14.0],
            [5.5, 4.8, -14.0],
            [3.5, 4.8, -14.0],
            [3.5, 4.8, -12.1],
            [0.0, 4.8, -12.1],
            [0.0, 4.8, -15.0],
            [0.0, 4.8, -17.2],
            [-4.45, 4.8, -17.2],
            [-4.45, 4.8, -14.5],
            [0.0, 2.0, -12.0],
            [3.2, 2.0, -14.0],
            [4.6, 2.0, -14.0],
            [-4.0, 2.0, 1.0],
            [5.8, 2.0, -1.0],
            [0.0, 2.0, 14.0],
            [0.0, 7.6, 14.0],
            [-4.0, 7.6, 1.0],
            [0.0, 7.6, -15.0],
            [0.0, 4.8, -16.0],
        ] {
            let mut arrived = false;
            for _ in 0..1200 {
                let p = state.players.iter().find(|p| p.id == id).unwrap();
                let here = [p.x, p.y - PLAYER_FLOOR_Y, p.z];
                if (here[0] - target[0]).hypot(here[2] - target[2]) < 0.3
                    && (here[1] - target[1]).abs() < 0.1
                {
                    arrived = true;
                    break;
                }
                let action = navigator.steer(
                    state.map.navigation(),
                    here,
                    NavigationGoal {
                        feet: target,
                        combat: false,
                    },
                    Action {
                        forward: true,
                        ..Default::default()
                    },
                    state.tick,
                    true,
                );
                let action = navigator.avoid_bodies(
                    &state.current_arena(),
                    id,
                    &state.contact_bodies(),
                    action,
                    state.tick,
                );
                assert!(!action.jump, "the actual crew routes remain walking routes");
                state.set_action(id, action);
                tick_without_guards(&mut state);
                state.take_events();
                assert!(
                    state.players.iter().find(|p| p.id == id).unwrap().hp >= 39,
                    "structural/contact fixture cannot cause damage"
                );
            }
            let p = state.players.iter().find(|p| p.id == id).unwrap();
            assert!(
                arrived,
                "crew edda={edda} splice={splice} known={known}, target={target:?} stalled at {:?}",
                [p.x, p.y - PLAYER_FLOOR_Y, p.z]
            );
        }
        assert_eq!(
            state.campaign_run_document().unwrap().unwrap().m10_transit,
            promoted.m10_transit
        );
        assert!(
            state
                .pickups
                .iter()
                .filter(|p| [
                    "passenger_medical",
                    "cargo_bullets",
                    "cargo_shells",
                    "repair_medical"
                ]
                .contains(&p.id.as_str()))
                .all(|p| !p.available),
            "ordinary contact-safe arrivals claim the actual finite supplies"
        );
        for _ in 0..400 {
            tick_without_guards(&mut state);
            state.take_events();
        }
        assert!(
            state
                .pickups
                .iter()
                .filter(|p| [
                    "passenger_medical",
                    "cargo_bullets",
                    "cargo_shells",
                    "repair_medical"
                ]
                .contains(&p.id.as_str()))
                .all(|p| !p.available),
            "campaign supplies never respawn while the mission continues"
        );
    }
}

#[test]
fn m10_actual_transit_bodies_stop_shots_and_unknown_people_do_not() {
    use crate::maps::EnemyPlacement;
    use crate::protocol::{Action, EnemyKind, ShotImpact, WeaponType};
    let source = crate::maps::AuthoredSource::Mission(MissionId::CommonCarrier)
        .load()
        .unwrap();
    let geometry = crate::maps::RuntimeMap::Authored(source.clone())
        .m10_geometry()
        .unwrap()
        .clone();
    let mut places = vec![("tern".to_owned(), geometry.pilot)];
    places.extend(geometry.passengers.iter().map(|p| (p.id.clone(), p.feet)));
    for (edda, splice, known) in [
        (false, false, true),
        (true, false, true),
        (false, true, true),
        (true, true, true),
        (true, true, false),
    ] {
        let mut before = m09_receipt_tests::completed_berth(edda, splice);
        if !known {
            before.m09_outcome = Some(M09Outcome::HistoricalUnrecorded {});
        }
        let promoted = before
            .promote_next(
                MissionId::CommonCarrier,
                crate::maps::RuntimeMap::Authored(source.clone())
                    .content_sha256()
                    .unwrap(),
            )
            .unwrap();
        for (name, feet) in &places {
            // Diagnostic rear guard and fixed firing lane use actual authored
            // civilian feet and the ordinary resolved shot owner. This is not
            // a route, encounter-roster or fresh-player difficulty fixture.
            let mut state = GameState::with_authored_map(source.clone());
            state.load_campaign_run(&promoted).unwrap();
            let shooter = Uuid::from_u128(1010);
            state.add_player(shooter, "ship shot visitor".into(), Role::Human);
            assert!(state.acknowledge_mission(
                shooter,
                MissionReady {
                    id: MissionId::CommonCarrier,
                    attempt: 1,
                }
            ));
            let rear = state.spawn_campaign_enemy(&EnemyPlacement {
                id: "diagnostic_rear_guard".into(),
                kind: EnemyKind::Clerk,
                feet: [feet[0] + 1.2, feet[1], feet[2]],
                yaw: 0.0,
                seated: false,
                armor: None,
                hover: None,
            });
            let rear_hp_before = state.players.iter().find(|p| p.id == rear).unwrap().hp;
            let owner = state.players.iter_mut().find(|p| p.id == shooter).unwrap();
            assert!(owner.inventory.owns(WeaponType::Sniper));
            [owner.x, owner.y, owner.z] = [feet[0] - 1.2, feet[1] + PLAYER_FLOOR_Y, feet[2]];
            owner.vy = 0.0;
            owner.fire_cooldown = 0;
            let mut expected_equipment =
                owner.inventory.saved_equipment(WeaponType::Sniper).unwrap();
            let cell = expected_equipment
                .ammo
                .iter_mut()
                .find(|count| count.pool == crate::protocol::AmmoPool::Cells)
                .unwrap();
            assert!(cell.rounds > 0);
            cell.rounds -= 1;
            state.spawn_shields.clear();
            let mut before_contacts = Vec::new();
            state.append_civilian_contacts(&mut before_contacts);
            let expected = name == "tern" || promoted.m10_transit.as_ref().unwrap().arrived(name);
            let key = format!("m10/{name}");
            assert_eq!(before_contacts.iter().any(|p| p.key == key), expected);
            state.set_action(
                shooter,
                Action {
                    fire: true,
                    weapon_swap: Some(WeaponType::Sniper),
                    yaw: Some(0.0),
                    pitch: Some(0.0),
                    ..Default::default()
                },
            );
            state.tick(0.0);
            let shots: Vec<_> = state
                .shot_results
                .iter()
                .filter(|shot| shot.shooter_id == shooter)
                .collect();
            assert_eq!(shots.len(), 1, "actual finite Sniper round for {key}");
            let shot = shots[0];
            let owner = state.players.iter().find(|p| p.id == shooter).unwrap();
            assert_eq!(owner.weapon, WeaponType::Sniper);
            assert_eq!(
                owner.inventory.saved_equipment(owner.weapon).unwrap(),
                expected_equipment,
                "one stopped or landed shot spends exactly one real Cell"
            );
            let rear_hp = state.players.iter().find(|p| p.id == rear).unwrap().hp;
            if expected {
                assert_eq!(shot.target_id, None, "civilian has no invented pawn HP");
                assert_eq!(shot.target_hp_after, None);
                assert_eq!(shot.damage, 0);
                assert!(!shot.hit && !shot.killed);
                assert_eq!(
                    rear_hp, rear_hp_before,
                    "real rear guard is occluded by {key}"
                );
                let trace = shot.trace.as_ref().unwrap();
                assert!(matches!(trace.impact, ShotImpact::Fighter { .. }));
                assert!((trace.end[0] - feet[0]).abs() <= crate::movement::RADIUS + 0.01);
            } else {
                assert_eq!(shot.target_id, Some(rear), "no phantom missing {key}");
                assert!(shot.hit && shot.damage > 0 && rear_hp < rear_hp_before);
            }
            let mut after_contacts = Vec::new();
            state.append_civilian_contacts(&mut after_contacts);
            assert_eq!(before_contacts.len(), after_contacts.len());
            for (before, after) in before_contacts.iter().zip(after_contacts) {
                assert_eq!(before.key, after.key);
                assert_eq!(before.from, after.from, "fire does not move real crew");
                assert_eq!(before.height, after.height);
                assert_eq!(before.radius, after.radius);
            }
            assert_eq!(
                state.campaign_run_document().unwrap().unwrap().m10_transit,
                promoted.m10_transit
            );
        }
    }
}
