//! Geometry compatibility uses exact actual worlds, never a hash allowlist.
use super::*;
use crate::maps::{AuthoredMap, RuntimeMap};
use crate::mission::run_file::{geometry, M12Outcome, SavedEntry, SavedStep};
use crate::protocol::{AmmoPool, BodyKind, WeaponType};

const PREDECESSORS: [&[u8]; 5] = [
    include_bytes!("fixtures/stair-predecessors-20261008/m08_custodian_of_record.json"),
    include_bytes!("fixtures/stair-predecessors-20261008/m09_passenger_manifest.json"),
    include_bytes!("fixtures/stair-predecessors-20261008/m10_common_carrier.json"),
    include_bytes!("fixtures/stair-predecessors-20261008/m12-terms-of-cooperation.json"),
    include_bytes!("fixtures/stair-predecessors-20261008/m09_passenger_manifest_enclosed.json"),
];

fn hashes() -> ContentHashes {
    let mut hashes = m09_tests::HASHES;
    for (mission, _, successor) in geometry::pairs() {
        hashes[stage_index(mission)] = successor;
    }
    hashes
}

fn entry(mission: MissionId, hash: [u8; 32]) -> RunDocument {
    let mut document = match mission {
        MissionId::CustodianOfRecord => {
            let mut completed = m09_tests::completed_archive();
            let SavedStep::AwaitingMission { exit, .. } = &completed.step else {
                panic!("archive completion")
            };
            completed.step = SavedStep::MissionEntry {
                mission,
                entry: exit.clone(),
            };
            completed.m08_outcome = None;
            completed
        }
        MissionId::PassengerManifest => m09_tests::completed_archive()
            .promote_next(mission, hash)
            .unwrap(),
        MissionId::CommonCarrier => m09_receipt_tests::completed_berth(true, true)
            .promote_next(mission, hash)
            .unwrap(),
        MissionId::TermsOfCooperation => arc_tests::completed_tender()
            .promote_next(mission, hash)
            .unwrap(),
        _ => panic!("unregistered geometry stage"),
    };
    document.content_sha256 = hash;
    document.body = Some(BodyKind::Synthetic);
    document.remaining_continues = 1;
    document.level_start_continues = 2;
    let SavedStep::MissionEntry { entry, .. } = &mut document.step else {
        panic!("mission entry")
    };
    entry.hp = 37;
    entry.armor = 19;
    entry.equipment.grenades = 2;
    entry.equipment.proximity_mines = 3;
    entry.equipment.personal_claims = vec!["actual_old_personal_stock".into()];
    for ammo in &mut entry.equipment.ammo {
        ammo.rounds = match ammo.pool {
            AmmoPool::Bullets => 23,
            AmmoPool::Shells => 7,
            AmmoPool::Cells => 5,
        };
    }
    document.validate(hash).unwrap();
    document
}

fn saved_entry(document: &RunDocument) -> SavedEntry {
    match &document.step {
        SavedStep::MissionEntry { entry, .. }
        | SavedStep::PendingContinue { entry, .. }
        | SavedStep::Failed { entry, .. }
        | SavedStep::Abandoned { entry, .. } => entry.clone(),
        SavedStep::AwaitingMission { exit, .. } => exit.clone(),
    }
}

fn completed(mission: MissionId, hash: [u8; 32]) -> RunDocument {
    let mut document = match mission {
        MissionId::CustodianOfRecord => m09_tests::completed_archive(),
        MissionId::PassengerManifest => m09_receipt_tests::completed_berth(true, true),
        MissionId::CommonCarrier => {
            let mut document = entry(mission, hash);
            let mut exit = saved_entry(&document);
            exit.equipment.weapons.push(WeaponType::Repeater);
            exit.equipment.selected = WeaponType::Repeater;
            document.step = SavedStep::AwaitingMission {
                completed_mission: mission,
                next_mission: "right_of_search".into(),
                exit,
            };
            document
        }
        MissionId::TermsOfCooperation => {
            let mut document = entry(mission, hash);
            let mut exit = saved_entry(&document);
            exit.equipment.weapons.push(WeaponType::Arc);
            exit.equipment.selected = WeaponType::Arc;
            document.step = SavedStep::AwaitingMission {
                completed_mission: mission,
                next_mission: "weight_of_permission".into(),
                exit,
            };
            document.m12_outcome = Some(M12Outcome {
                shelter_opened: true,
                workers_released: false,
                pump_health: [100, 63],
                assessor_wreck_union_kills: 3,
                pumps_intact_at_route_secure: true,
            });
            document
        }
        _ => panic!("unregistered completion"),
    };
    document.content_sha256 = hash;
    document.validate(hash).unwrap();
    document
}

fn original_bytes(document: &RunDocument) -> Vec<u8> {
    let mut bytes = serde_json::to_vec_pretty(document).unwrap();
    bytes.extend_from_slice(b"\n \t\n");
    bytes
}

#[test]
fn geometry_registered_predecessors_are_exact_strict_loaded_mission_worlds() {
    for ((mission, predecessor, successor), bytes) in geometry::pairs().zip(PREDECESSORS) {
        assert_ne!(predecessor, successor);
        assert_eq!(<[u8; 32]>::from(Sha256::digest(bytes)), predecessor);
        let map = RuntimeMap::Authored(AuthoredMap::read(bytes).unwrap());
        assert_eq!(map.campaign_mission_id(), Some(mission));
        assert_eq!(map.content_sha256(), Some(predecessor));
        let current = crate::maps::AuthoredSource::bundled_content_sha256(mission);
        assert_eq!(
            current, successor,
            "canonical source must be the registered exact successor"
        );
    }
}

#[test]
fn geometry_current_entry_and_pending_upgrade_archive_exact_bytes_without_changing_state() {
    for (mission, predecessor, successor) in geometry::pairs() {
        for pending in [false, true] {
            let mut source = entry(mission, predecessor);
            if pending {
                source.step = SavedStep::PendingContinue {
                    mission,
                    entry: saved_entry(&source),
                };
            }
            let bytes = original_bytes(&source);
            let directory = std::env::temp_dir().join(format!("fragr-geometry-{}", Uuid::new_v4()));
            let store = RunStore::open_with_hashes(&directory, hashes()).unwrap();
            fs::write(directory.join(RUN_NAME), &bytes).unwrap();
            let mut expected = source.clone();
            expected.content_sha256 = successor;
            let preview = RunStore::preview_with_hashes(&directory, hashes())
                .unwrap()
                .unwrap();
            assert_eq!(preview, expected, "only identity changes");
            assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
            assert_eq!(
                fs::read_dir(&directory).unwrap().count(),
                2,
                "preview never writes"
            );
            assert!(
                store.needs_upgrade().unwrap(),
                "same-version geometry needs archival"
            );
            let loaded = store.load().unwrap().unwrap();
            let archive = store.archive_and_save(&loaded, &loaded).unwrap();
            assert_eq!(
                fs::read(&archive).unwrap(),
                bytes,
                "not a reserialized backup"
            );
            assert_eq!(store.load().unwrap(), Some(expected.clone()));
            assert!(!store.needs_upgrade().unwrap());
            assert_eq!(fs::read_dir(&directory).unwrap().count(), 3);
            drop(store);
            let reopened = RunStore::open_with_hashes(&directory, hashes()).unwrap();
            assert_eq!(reopened.load().unwrap(), Some(expected));
            drop(reopened);
            fs::remove_dir_all(directory).unwrap();
        }
    }
}

#[test]
fn geometry_each_reachable_historical_shape_validates_before_identity_normalization() {
    for (mission, predecessor, successor) in geometry::pairs() {
        let first = geometry::first_version(mission, predecessor);
        for version in first..=14 {
            for pending in [false, true] {
                let mut source = entry(mission, predecessor);
                if pending {
                    source.step = SavedStep::PendingContinue {
                        mission,
                        entry: saved_entry(&source),
                    };
                }
                let mut value = serde_json::to_value(&source).unwrap();
                value["version"] = version.into();
                value["rules"]["revision"] = 3.into();
                if version < 14 {
                    assert_eq!(saved_entry(&source).equipment.remote_mines, 0);
                    let equipment = value["step"]["entry"]["equipment"].as_object_mut().unwrap();
                    if let Some(remote_mines) = equipment.remove("remote_mines") {
                        assert_eq!(remote_mines, 0);
                    }
                }
                let mut predecessor_hashes = hashes();
                predecessor_hashes[stage_index(mission)] = predecessor;
                let bytes = serde_json::to_vec(&value).unwrap();
                let RunProbe::Compatible(mut expected) =
                    RunStore::inspect_bytes(&bytes, predecessor_hashes)
                else {
                    panic!("valid actual historical v{version} {mission:?} first")
                };
                assert_eq!(expected.content_sha256, predecessor);
                expected.content_sha256 = successor;
                let RunProbe::Compatible(actual) = RunStore::inspect_bytes(&bytes, hashes()) else {
                    panic!("historical geometry v{version} {mission:?}")
                };
                assert_eq!(actual, expected);
                let mut forged = value.clone();
                forged["rules"]["revision"] = 4.into();
                assert!(matches!(
                    RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), hashes()),
                    RunProbe::Incompatible
                ));
                for field in ["selected", "weapons"] {
                    let mut forged = value.clone();
                    if field == "selected" {
                        forged["step"]["entry"]["equipment"][field] = "arc".into();
                    } else {
                        forged["step"]["entry"]["equipment"][field]
                            .as_array_mut()
                            .unwrap()
                            .push("arc".into());
                    }
                    assert!(matches!(
                        RunStore::inspect_bytes(&serde_json::to_vec(&forged).unwrap(), hashes()),
                        RunProbe::Corrupt
                    ));
                }
            }
        }
    }
}

#[test]
fn geometry_completion_and_closed_history_keep_the_original_world_identity() {
    for (mission, predecessor, _) in geometry::pairs() {
        let mut documents = vec![completed(mission, predecessor)];
        for failed in [false, true] {
            let mut source = entry(mission, predecessor);
            let entry = saved_entry(&source);
            source.step = if failed {
                source.remaining_continues = 0;
                SavedStep::Failed { mission, entry }
            } else {
                SavedStep::Abandoned { mission, entry }
            };
            documents.push(source);
        }
        for source in documents {
            let bytes = original_bytes(&source);
            let RunProbe::Compatible(actual) = RunStore::inspect_bytes(&bytes, hashes()) else {
                panic!("closed or completed historical world")
            };
            assert_eq!(
                *actual, source,
                "old completion cannot claim new geometry was played"
            );
            let directory =
                std::env::temp_dir().join(format!("fragr-geometry-history-{}", Uuid::new_v4()));
            let store = RunStore::open_with_hashes(&directory, hashes()).unwrap();
            fs::write(directory.join(RUN_NAME), &bytes).unwrap();
            assert!(!store.needs_upgrade().unwrap());
            assert!(
                store.save(&source).is_err(),
                "a closed predecessor cannot be rewritten as current"
            );
            if let SavedStep::AwaitingMission { .. } = &source.step {
                let next = match mission {
                    MissionId::CustodianOfRecord => Some(MissionId::PassengerManifest),
                    MissionId::PassengerManifest => Some(MissionId::CommonCarrier),
                    MissionId::CommonCarrier => Some(MissionId::RightOfSearch),
                    MissionId::TermsOfCooperation => None,
                    _ => unreachable!(),
                };
                if let Some(next) = next {
                    let target = source
                        .promote_next(next, hashes()[stage_index(next)])
                        .unwrap();
                    let archive = store.archive_and_save(&source, &target).unwrap();
                    assert_eq!(fs::read(archive).unwrap(), bytes);
                    assert_eq!(store.load().unwrap(), Some(target.clone()));
                    assert_eq!(target.m03_outcome, source.m03_outcome);
                    assert_eq!(target.m04_outcome, source.m04_outcome);
                    assert_eq!(target.m05_outcome, source.m05_outcome);
                    assert_eq!(target.m08_outcome, source.m08_outcome);
                    assert_eq!(
                        target.remaining_continues,
                        if next == MissionId::CommonCarrier {
                            3
                        } else {
                            source.remaining_continues
                        }
                    );
                }
            }
            drop(store);
            fs::remove_dir_all(directory).unwrap();
        }
    }
}

#[test]
fn geometry_m09_intermediate_cannot_claim_a_historical_document_revision() {
    let mission = MissionId::PassengerManifest;
    let predecessor = <[u8; 32]>::from(Sha256::digest(PREDECESSORS[4]));
    assert_eq!(geometry::first_version(mission, predecessor), 15);
    for kind in 0..5 {
        let mut document = if kind == 4 {
            completed(mission, predecessor)
        } else {
            entry(mission, predecessor)
        };
        let entry = saved_entry(&document);
        match kind {
            1 => document.step = SavedStep::PendingContinue { mission, entry },
            2 => {
                document.remaining_continues = 0;
                document.step = SavedStep::Failed { mission, entry };
            }
            3 => document.step = SavedStep::Abandoned { mission, entry },
            _ => {}
        }
        let mut value = serde_json::to_value(&document).unwrap();
        value["version"] = 14.into();
        value["rules"]["revision"] = 3.into();
        let bytes = serde_json::to_vec(&value).unwrap();
        let mut predecessor_hashes = hashes();
        predecessor_hashes[stage_index(mission)] = predecessor;
        assert!(matches!(
            RunStore::inspect_bytes(&bytes, predecessor_hashes),
            RunProbe::Compatible(_)
        ));
        assert!(matches!(
            RunStore::inspect_bytes(&bytes, hashes()),
            RunProbe::Incompatible
        ));
    }
}

#[test]
fn geometry_historical_completion_and_closed_runs_preserve_bytes_until_promotion_or_new_run() {
    for (mission, predecessor, _) in geometry::pairs() {
        let first = geometry::first_version(mission, predecessor);
        for version in first..=14 {
            for closed in [None, Some(false), Some(true)] {
                let mut source = if closed.is_some() {
                    entry(mission, predecessor)
                } else {
                    completed(mission, predecessor)
                };
                if let Some(failed) = closed {
                    let entry = saved_entry(&source);
                    source.step = if failed {
                        source.remaining_continues = 0;
                        SavedStep::Failed { mission, entry }
                    } else {
                        SavedStep::Abandoned { mission, entry }
                    };
                }
                let mut value = serde_json::to_value(&source).unwrap();
                value["version"] = version.into();
                value["rules"]["revision"] = 3.into();
                if version < 14 {
                    let key = if closed.is_some() { "entry" } else { "exit" };
                    assert_eq!(saved_entry(&source).equipment.remote_mines, 0);
                    if let Some(count) = value["step"][key]["equipment"]
                        .as_object_mut()
                        .unwrap()
                        .remove("remote_mines")
                    {
                        assert_eq!(count, 0);
                    }
                }
                if version == 9 {
                    value.as_object_mut().unwrap().remove("m08_outcome");
                }
                if version <= 11 {
                    value.as_object_mut().unwrap().remove("m09_outcome");
                }
                let mut bytes = serde_json::to_vec_pretty(&value).unwrap();
                bytes.extend_from_slice(b"\n \t\n");
                let mut historical_hashes = hashes();
                historical_hashes[stage_index(mission)] = predecessor;
                let RunProbe::Compatible(expected) =
                    RunStore::inspect_bytes(&bytes, historical_hashes)
                else {
                    panic!("valid historical completed/closed v{version} {mission:?}")
                };
                let directory = std::env::temp_dir()
                    .join(format!("fragr-geometry-old-history-{}", Uuid::new_v4()));
                let store = RunStore::open_with_hashes(&directory, hashes()).unwrap();
                fs::write(directory.join(RUN_NAME), &bytes).unwrap();
                let actual = store.load().unwrap().unwrap();
                assert_eq!(actual, *expected);
                assert_eq!(actual.content_sha256, predecessor);
                assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
                assert!(
                    store.needs_upgrade().unwrap(),
                    "old schema remains detectable"
                );
                if closed.is_some() {
                    assert!(store.archive_and_save(&actual, &actual).is_err());
                    assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
                    let new = RunDocument::new(
                        Uuid::new_v4(),
                        crate::protocol::CampaignRules::default(),
                        hashes()[0],
                    );
                    let archive = store.start_new(&new).unwrap().unwrap();
                    assert_eq!(fs::read(archive).unwrap(), bytes);
                    assert_eq!(store.load().unwrap(), Some(new));
                } else {
                    let next = match mission {
                        MissionId::CustodianOfRecord => MissionId::PassengerManifest,
                        MissionId::PassengerManifest => MissionId::CommonCarrier,
                        MissionId::CommonCarrier => MissionId::RightOfSearch,
                        _ => unreachable!(),
                    };
                    let promoted = actual
                        .promote_next(next, hashes()[stage_index(next)])
                        .unwrap();
                    let archive = store.archive_and_save(&actual, &promoted).unwrap();
                    assert_eq!(fs::read(archive).unwrap(), bytes);
                    assert_eq!(store.load().unwrap(), Some(promoted));
                }
                drop(store);
                fs::remove_dir_all(directory).unwrap();
            }
        }
    }
}

#[test]
fn geometry_refuses_unknown_hash_wrong_stage_malformed_or_unregistered_successor() {
    for ((mission, predecessor, _), bytes) in geometry::pairs().zip(PREDECESSORS) {
        let source = entry(mission, predecessor);
        let mut changed_map = bytes.to_vec();
        changed_map.push(b' ');
        let changed_hash = <[u8; 32]>::from(Sha256::digest(&changed_map));
        assert_eq!(
            RuntimeMap::Authored(AuthoredMap::read(changed_map.as_slice()).unwrap())
                .campaign_mission_id(),
            Some(mission),
            "a semantically unchanged one-byte source alteration still has its own identity"
        );
        let mut changed_source = source.clone();
        changed_source.content_sha256 = changed_hash;
        assert!(matches!(
            RunStore::inspect_bytes(&original_bytes(&changed_source), hashes()),
            RunProbe::Incompatible
        ));
        let mut unknown = source.clone();
        unknown.content_sha256[0] ^= 1;
        assert!(matches!(
            RunStore::inspect_bytes(&original_bytes(&unknown), hashes()),
            RunProbe::Incompatible
        ));
        let mut future = hashes();
        future[stage_index(mission)][0] ^= 1;
        assert!(matches!(
            RunStore::inspect_bytes(&original_bytes(&source), future),
            RunProbe::Incompatible
        ));
        let mut wrong = source.clone();
        wrong.step = SavedStep::MissionEntry {
            mission: MissionId::RecallNotice,
            entry: saved_entry(&source),
        };
        assert!(matches!(
            RunStore::inspect_bytes(&original_bytes(&wrong), hashes()),
            RunProbe::Incompatible
        ));
        let mut value = serde_json::to_value(&source).unwrap();
        value["step"]["entry"]["equipment"]["grenades"] = 7.into();
        assert!(!matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), hashes()),
            RunProbe::Compatible(_)
        ));
        value = serde_json::to_value(&source).unwrap();
        value["step"]["entry"]["equipment"]["unknown_stock"] = true.into();
        assert!(matches!(
            RunStore::inspect_bytes(&serde_json::to_vec(&value).unwrap(), hashes()),
            RunProbe::Corrupt
        ));
    }
}

#[test]
fn geometry_failed_replace_conflicts_and_retry_preserve_exact_original() {
    for (mission, predecessor, _) in geometry::pairs() {
        let source = entry(mission, predecessor);
        let bytes = original_bytes(&source);
        let directory =
            std::env::temp_dir().join(format!("fragr-geometry-fault-{}", Uuid::new_v4()));
        let store = RunStore::open_with_hashes(&directory, hashes()).unwrap();
        let path = directory.join(RUN_NAME);
        fs::write(&path, &bytes).unwrap();
        let loaded = store.load().unwrap().unwrap();
        assert!(store
            .archive_and_save_before_replace(&loaded, &loaded, |_| Err(io::Error::other(
                "injected geometry replacement failure"
            )))
            .is_err());
        assert_eq!(fs::read(&path).unwrap(), bytes);
        assert!(store.needs_upgrade().unwrap());
        let digest: String = Sha256::digest(&bytes)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect();
        let archive = directory.join(format!("run.prior-{digest}.json"));
        assert_eq!(fs::read(&archive).unwrap(), bytes);
        fs::write(&archive, b"conflicting archive").unwrap();
        assert!(store.archive_and_save(&loaded, &loaded).is_err());
        assert_eq!(fs::read(&path).unwrap(), bytes);
        fs::write(&archive, &bytes).unwrap();
        let mut changed = source.clone();
        changed.remaining_continues = 0;
        let changed_bytes = original_bytes(&changed);
        assert!(store
            .archive_and_save_before_replace(&loaded, &loaded, |_| fs::write(&path, &changed_bytes))
            .is_err());
        assert_eq!(fs::read(&path).unwrap(), changed_bytes);
        assert!(store.archive_and_save(&loaded, &loaded).is_err());
        fs::write(&path, &bytes).unwrap();
        assert_eq!(store.archive_and_save(&loaded, &loaded).unwrap(), archive);
        assert!(!store.needs_upgrade().unwrap());
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 3);
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }
}

async fn resume_through_owned_runner(
    directory: &Path,
    mission: MissionId,
) -> Result<RunDocument, String> {
    use crate::maps::AuthoredSource;
    use crate::run::{run_local_server, LocalRunConfig, ServerOptions};
    use std::cell::Cell;
    use std::time::{Duration, Instant};
    use tokio::sync::oneshot;
    let raw: serde_json::Value =
        serde_json::from_slice(&fs::read(directory.join(RUN_NAME)).unwrap()).unwrap();
    let source_hash: [u8; 32] = serde_json::from_value(raw["content_sha256"].clone()).unwrap();
    let prefix: String = source_hash[..4]
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    let case = format!("{mission:?}/{}/{prefix}", raw["step"]["kind"]);
    let started = Instant::now();
    let phase = Cell::new("waiting_ready");
    let (ready_tx, mut ready_rx) = oneshot::channel();
    let (difficulty_tx, difficulty_rx) = oneshot::channel();
    let (stop_tx, stop_rx) = oneshot::channel();
    let server = run_local_server(
        ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(AuthoredSource::Mission(mission)),
            campaign_run: true,
            status_every_s: 0,
            ..ServerOptions::default()
        },
        async {
            let _ = stop_rx.await;
        },
        ready_tx,
        LocalRunConfig {
            directory: directory.to_owned(),
            resume: true,
            difficulty_ready: difficulty_tx,
        },
    );
    tokio::pin!(server);
    let result = tokio::time::timeout(Duration::from_secs(30), async {
        tokio::select! {
            result = &mut server => {
                phase.set("refused");
                Err(result.expect_err("runner must remain live after readiness").to_string())
            },
            ready = &mut ready_rx => {
                if let Ok(address) = ready {
                    phase.set("ready_received");
                    assert!(address.ip().is_loopback());
                    assert_ne!(address.port(), 0);
                    let document: RunDocument = serde_json::from_slice(&fs::read(directory.join(RUN_NAME)).unwrap()).unwrap();
                    assert_eq!(difficulty_rx.await.unwrap(), document.rules.difficulty);
                    phase.set("shutdown_requested");
                    let _ = stop_tx.send(());
                    server.await.map_err(|error| error.to_string())?;
                    phase.set("stopped");
                    Ok(document)
                } else {
                    phase.set("refusal_confirmation");
                    Err(server.await.expect_err("closed readiness needs a launch refusal").to_string())
                }
            }
        }
    }).await.unwrap_or_else(|_| panic!("owned local geometry runner deadline: {case}, phase {}, elapsed {:?}", phase.get(), started.elapsed()));
    eprintln!(
        "owned geometry runner {case}, phase {}, elapsed {:?}",
        phase.get(),
        started.elapsed()
    );
    result
}

#[tokio::test]
async fn geometry_owned_local_launch_archives_same_version_entries_and_pending_without_refill() {
    for (mission, predecessor, successor) in geometry::pairs() {
        assert_eq!(
            crate::maps::AuthoredSource::bundled_content_sha256(mission),
            successor
        );
        for pending in [false, true] {
            let mut source = entry(mission, predecessor);
            if pending {
                source.step = SavedStep::PendingContinue {
                    mission,
                    entry: saved_entry(&source),
                };
            }
            let bytes = original_bytes(&source);
            let directory =
                std::env::temp_dir().join(format!("fragr-geometry-owned-entry-{}", Uuid::new_v4()));
            fs::create_dir_all(&directory).unwrap();
            fs::write(directory.join(RUN_NAME), &bytes).unwrap();
            let actual = resume_through_owned_runner(&directory, mission)
                .await
                .unwrap();
            let mut expected = source.clone();
            expected.content_sha256 = successor;
            assert_eq!(actual, expected);
            let archives: Vec<_> = fs::read_dir(&directory)
                .unwrap()
                .filter_map(Result::ok)
                .filter(|file| file.file_name().to_string_lossy().starts_with("run.prior-"))
                .collect();
            assert_eq!(archives.len(), 1);
            assert_eq!(fs::read(archives[0].path()).unwrap(), bytes);
            assert_eq!(
                resume_through_owned_runner(&directory, mission)
                    .await
                    .unwrap(),
                expected
            );
            assert_eq!(
                fs::read_dir(&directory)
                    .unwrap()
                    .filter_map(Result::ok)
                    .filter(|file| file.file_name().to_string_lossy().starts_with("run.prior-"))
                    .count(),
                1,
                "restart cannot archive or refill twice"
            );
            fs::remove_dir_all(directory).unwrap();
        }
    }
}

#[tokio::test]
async fn geometry_owned_local_promotion_keeps_predecessor_completion_and_archives_before_next_entry(
) {
    for (mission, predecessor, _) in geometry::pairs() {
        let next = match mission {
            MissionId::CustodianOfRecord => MissionId::PassengerManifest,
            MissionId::PassengerManifest => MissionId::CommonCarrier,
            MissionId::CommonCarrier => MissionId::RightOfSearch,
            MissionId::TermsOfCooperation => continue,
            _ => unreachable!(),
        };
        let source = completed(mission, predecessor);
        let bytes = original_bytes(&source);
        let directory =
            std::env::temp_dir().join(format!("fragr-geometry-owned-promotion-{}", Uuid::new_v4()));
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join(RUN_NAME), &bytes).unwrap();
        let expected = source
            .promote_next(
                next,
                crate::maps::AuthoredSource::bundled_content_sha256(next),
            )
            .unwrap();
        let actual = resume_through_owned_runner(&directory, next).await.unwrap();
        assert_eq!(actual, expected);
        let archives: Vec<_> = fs::read_dir(&directory)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|file| file.file_name().to_string_lossy().starts_with("run.prior-"))
            .collect();
        assert_eq!(archives.len(), 1);
        assert_eq!(
            fs::read(archives[0].path()).unwrap(),
            bytes,
            "archive remains the original completed world, not the successor identity"
        );
        assert_eq!(
            resume_through_owned_runner(&directory, next).await.unwrap(),
            expected
        );
        fs::remove_dir_all(directory).unwrap();
    }
}

#[tokio::test]
async fn geometry_owned_local_refuses_historical_closed_runs_before_any_version_upgrade() {
    for (mission, predecessor, _) in geometry::pairs() {
        let old_version = geometry::first_version(mission, predecessor);
        for failed in [false, true] {
            let mut source = entry(mission, predecessor);
            let entry = saved_entry(&source);
            source.step = if failed {
                source.remaining_continues = 0;
                SavedStep::Failed { mission, entry }
            } else {
                SavedStep::Abandoned { mission, entry }
            };
            let mut value = serde_json::to_value(&source).unwrap();
            value["version"] = old_version.into();
            if old_version < 15 {
                value["rules"]["revision"] = 3.into();
            }
            if old_version < 14 {
                value["step"]["entry"]["equipment"]
                    .as_object_mut()
                    .unwrap()
                    .remove("remote_mines");
            }
            let bytes = serde_json::to_vec_pretty(&value).unwrap();
            let directory = std::env::temp_dir()
                .join(format!("fragr-geometry-owned-closed-{}", Uuid::new_v4()));
            fs::create_dir_all(&directory).unwrap();
            fs::write(directory.join(RUN_NAME), &bytes).unwrap();
            let error = resume_through_owned_runner(&directory, mission)
                .await
                .unwrap_err();
            assert!(error.contains("not playable"), "{error}");
            assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), bytes);
            assert_eq!(
                fs::read_dir(&directory).unwrap().count(),
                2,
                "closed history is refused before archival or replacement"
            );
            fs::remove_dir_all(directory).unwrap();
        }
    }
}

#[test]
fn geometry_successor_pending_continue_spends_once_and_actual_standing_entry_walks() {
    use crate::protocol::{Action, MissionContinue, MissionReady, Role};
    use crate::sim::{GameState, PLAYER_FLOOR_Y};
    fn assert_standing_support(arena: &crate::movement::Arena, feet: [f32; 3]) {
        let support =
            arena.support_height(feet[0], feet[2], feet[1] + crate::movement::CONTACT_EPSILON);
        assert!(
            (feet[1] - support).abs() <= crate::movement::CONTACT_EPSILON,
            "actual feet {feet:?} must agree with measured support {support}"
        );
        // Reference-height subtraction can put 0.3 m feet at 0.29999995.
        // Query the proven support without moving the player or shortening
        // the body, and reject any actual gap or penetration above epsilon.
        assert!(arena.fits_height(feet[0], feet[2], support, crate::movement::BODY_HEIGHT));
    }
    for (mission, predecessor, successor) in geometry::pairs() {
        let map = crate::maps::AuthoredSource::Mission(mission)
            .load()
            .unwrap();
        assert_eq!(
            RuntimeMap::Authored(map.clone()).content_sha256(),
            Some(successor)
        );
        for pending in [false, true] {
            let mut source = entry(mission, predecessor);
            if pending {
                source.step = SavedStep::PendingContinue {
                    mission,
                    entry: saved_entry(&source),
                };
            }
            let anchor = saved_entry(&source);
            let RunProbe::Compatible(document) =
                RunStore::inspect_bytes(&original_bytes(&source), hashes())
            else {
                panic!("validated exact successor entry")
            };
            let mut state = GameState::with_authored_map(map.clone());
            state.load_campaign_run(&document).unwrap();
            let owner = Uuid::new_v4();
            state.add_player(owner, "Visitor".into(), Role::Human);
            if pending {
                assert_eq!(
                    state
                        .players
                        .iter()
                        .find(|player| player.id == owner)
                        .unwrap()
                        .hp,
                    0
                );
                let request = MissionContinue {
                    id: mission,
                    run_id: document.id,
                    attempt: document.attempt(),
                };
                assert!(state.continue_mission(owner, request));
                assert!(
                    !state.continue_mission(owner, request),
                    "a repeated continue cannot spend twice"
                );
            }
            let saved = state.campaign_run_document().unwrap().unwrap();
            assert_eq!(saved.content_sha256, successor);
            assert_eq!(
                saved.remaining_continues,
                document.remaining_continues - u8::from(pending)
            );
            assert_eq!(saved.level_start_continues, document.level_start_continues);
            assert_eq!(saved_entry(&saved), anchor);
            assert_eq!(saved.body, document.body);
            assert_eq!(saved.m03_outcome, document.m03_outcome);
            assert_eq!(saved.m04_outcome, document.m04_outcome);
            assert_eq!(saved.m05_outcome, document.m05_outcome);
            assert_eq!(saved.m08_outcome, document.m08_outcome);
            assert_eq!(saved.m09_outcome, document.m09_outcome);
            assert_eq!(saved.m10_transit, document.m10_transit);
            assert_eq!(saved.m11_outcome, document.m11_outcome);
            let acknowledged = state.acknowledge_mission(
                owner,
                MissionReady {
                    id: mission,
                    attempt: saved.attempt(),
                },
            );
            assert_eq!(
                acknowledged, !pending,
                "a restored continue already retains readiness; a fresh entry still needs acknowledgement"
            );
            let player = state
                .players
                .iter()
                .find(|player| player.id == owner)
                .unwrap();
            assert_eq!(SavedEntry::from_player(player).unwrap(), anchor);
            let start = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            assert_standing_support(state.map.arena(), start);
            state.set_action(
                owner,
                Action {
                    forward: true,
                    yaw: Some(std::f32::consts::FRAC_PI_2),
                    ..Action::default()
                },
            );
            for _ in 0..6 {
                state.tick(0.05);
                let player = state
                    .players
                    .iter()
                    .find(|player| player.id == owner)
                    .unwrap();
                assert!(
                    !player.ducking,
                    "the successor spawn uses ordinary full standing clearance"
                );
                assert_standing_support(
                    state.map.arena(),
                    [player.x, player.y - PLAYER_FLOOR_Y, player.z],
                );
                assert!(player.hp > 0);
            }
            let player = state
                .players
                .iter()
                .find(|player| player.id == owner)
                .unwrap();
            assert!(
                player.z - start[2] >= 1.0,
                "ordinary initial route became blocked in {mission:?}"
            );
            assert!(
                (player.y - PLAYER_FLOOR_Y - start[1]).abs() < 0.05,
                "successor entry lost its real floor"
            );
        }
    }
}
