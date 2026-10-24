//! Bounded local run storage. One process holds the writer lock, and every
//! write atomically replaces `run.json`. The lock file is never renamed.
//!
//! Only [`RUN_FILE_VERSION`] is readable. Any other version is reported as
//! [`RunProbe::Incompatible`] and unreadable bytes as [`RunProbe::Corrupt`];
//! the menu then offers a new run, which simply replaces the file.
use super::{RunDocument, RUN_FILE_VERSION};
use crate::protocol::MissionId;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use uuid::Uuid;

const MAX_RUN_BYTES: u64 = 65_536;
const RUN_NAME: &str = "run.json";
const LOCK_NAME: &str = "run.lock";

/// Internally supported save stages, independent of network capability admission.
pub(crate) const CAMPAIGN_STAGES: usize = MissionId::ALL.len();
/// Bundled content hashes for every playable campaign stage.
pub(crate) type ContentHashes = [[u8; 32]; CAMPAIGN_STAGES];

/// Every playable campaign stage, indexed like [`ContentHashes`].
pub(crate) const CAMPAIGN_MISSIONS: [MissionId; CAMPAIGN_STAGES] = MissionId::ALL;

/// Index of a playable mission in [`ContentHashes`].
pub(crate) const fn stage_index(mission: MissionId) -> usize {
    match mission {
        MissionId::RecallNotice => 0,
        MissionId::PersonsUnknown => 1,
        MissionId::ScheduledService => 2,
        MissionId::NoticeToVacate => 3,
        MissionId::NoForwardingAddress => 4,
        MissionId::PortOfEntry => 5,
        MissionId::DeclaredGoods => 6,
        MissionId::CustodianOfRecord => 7,
        MissionId::PassengerManifest => 8,
        MissionId::CommonCarrier => 9,
        MissionId::RightOfSearch => 10,
        MissionId::TermsOfCooperation => 11,
        MissionId::WeightOfPermission => 12,
        MissionId::LaunchAuthority => 13,
        MissionId::CivicPressureValve => 14,
        MissionId::FreedomOfMovement => 15,
        MissionId::PeaceWithoutInterruption => 16,
        MissionId::AllSystemsNormal => 17,
    }
}

pub(crate) struct RunStore {
    directory: PathBuf,
    hashes: ContentHashes,
    _lock: File,
}

pub(crate) enum RunProbe {
    Missing,
    Compatible(Box<RunDocument>),
    /// Readable JSON this build will not continue: another schema version,
    /// different bundled mission content, or a document that fails validation.
    Incompatible,
    /// Oversized, not JSON, missing its version, or not the current shape.
    Corrupt,
}

impl RunStore {
    /// Only the local child opens a writable run. Tests supply an isolated dir.
    #[cfg(test)]
    pub fn open(directory: &Path, content_sha256: [u8; 32]) -> io::Result<Self> {
        Self::open_with_hashes(directory, [content_sha256; CAMPAIGN_STAGES])
    }

    pub fn open_with_hashes(directory: &Path, hashes: ContentHashes) -> io::Result<Self> {
        fs::create_dir_all(directory)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(directory.join(LOCK_NAME))?;
        lock.try_lock()?;
        Ok(Self {
            directory: directory.to_owned(),
            hashes,
            _lock: lock,
        })
    }

    pub fn load(&self) -> io::Result<Option<RunDocument>> {
        Self::preview_with_hashes(&self.directory, self.hashes)
    }

    /// A menu may inspect an unlocked snapshot. Launch always reopens under
    /// the writer lock and validates again before advertising readiness.
    pub fn preview_with_hashes(
        directory: &Path,
        hashes: ContentHashes,
    ) -> io::Result<Option<RunDocument>> {
        match Self::inspect_with_hashes(directory, hashes)? {
            RunProbe::Missing => Ok(None),
            RunProbe::Compatible(document) => Ok(Some(*document)),
            RunProbe::Incompatible => Err(invalid("incompatible campaign run document")),
            RunProbe::Corrupt => Err(invalid("invalid campaign run document")),
        }
    }

    #[cfg(test)]
    pub fn inspect(directory: &Path, content_sha256: [u8; 32]) -> io::Result<RunProbe> {
        Self::inspect_with_hashes(directory, [content_sha256; CAMPAIGN_STAGES])
    }

    pub fn inspect_with_hashes(directory: &Path, hashes: ContentHashes) -> io::Result<RunProbe> {
        let file = match File::open(directory.join(RUN_NAME)) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(RunProbe::Missing),
            Err(error) => return Err(error),
        };
        let mut bytes = Vec::new();
        file.take(MAX_RUN_BYTES + 1).read_to_end(&mut bytes)?;
        Ok(Self::inspect_bytes(&bytes, hashes))
    }

    fn inspect_bytes(bytes: &[u8], hashes: ContentHashes) -> RunProbe {
        if bytes.len() as u64 > MAX_RUN_BYTES {
            return RunProbe::Corrupt;
        }
        let Ok(value) = serde_json::from_slice::<serde_json::Value>(bytes) else {
            return RunProbe::Corrupt;
        };
        match value.get("version").and_then(serde_json::Value::as_u64) {
            Some(version) if version == u64::from(RUN_FILE_VERSION) => {}
            Some(_) => return RunProbe::Incompatible,
            None => return RunProbe::Corrupt,
        }
        let Ok(document) = serde_json::from_value::<RunDocument>(value) else {
            return RunProbe::Corrupt;
        };
        if document
            .validate(hashes[stage_index(document.stage_mission())])
            .is_err()
        {
            return RunProbe::Incompatible;
        }
        RunProbe::Compatible(Box::new(document))
    }

    fn expected_hash(&self, document: &RunDocument) -> [u8; 32] {
        self.hashes[stage_index(document.stage_mission())]
    }

    /// Validate and atomically replace `run.json`, whatever it held before.
    /// New Run, promotion between missions and in-mission checkpoints all
    /// write through here under the writer lock.
    pub fn save(&self, document: &RunDocument) -> io::Result<()> {
        self.save_with_sync(document, |_| Ok(()), sync_directory)
    }

    fn save_with_sync(
        &self,
        document: &RunDocument,
        before_replace: impl FnOnce(&Path) -> io::Result<()>,
        sync: impl Fn(&Path) -> io::Result<()>,
    ) -> io::Result<()> {
        document
            .validate(self.expected_hash(document))
            .map_err(invalid)?;
        let bytes = serde_json::to_vec(document)
            .map_err(|_| invalid("campaign run document could not be encoded"))?;
        if bytes.len() as u64 > MAX_RUN_BYTES {
            return Err(invalid("campaign run document exceeds the size limit"));
        }
        let temporary = self
            .directory
            .join(format!("run.{}.tmp", Uuid::new_v4().simple()));
        let mut replaced = false;
        let result = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)?;
            file.write_all(&bytes)?;
            file.sync_all()?;
            drop(file);
            before_replace(&temporary)?;
            fs::rename(&temporary, self.directory.join(RUN_NAME))?;
            replaced = true;
            sync(&self.directory)
        })();
        if let Err(error) = result {
            if replaced {
                let mut current = Vec::new();
                let matches_new = File::open(self.directory.join(RUN_NAME))
                    .and_then(|file| file.take(MAX_RUN_BYTES + 1).read_to_end(&mut current))
                    .is_ok_and(|_| current == bytes);
                return Err(io::Error::new(
                    error.kind(),
                    if matches_new {
                        format!(
                            "new campaign run is live; directory durability is uncertain: {error}"
                        )
                    } else {
                        format!("campaign run replacement location is uncertain: {error}")
                    },
                ));
            }
            // A failed pre-rename write leaves only this unique temporary file.
            let _ = fs::remove_file(&temporary);
            return Err(error);
        }
        Ok(())
    }
}

fn invalid(reason: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, reason)
}

#[cfg(unix)]
fn sync_directory(directory: &Path) -> io::Result<()> {
    File::open(directory)?.sync_all()
}

#[cfg(not(unix))]
fn sync_directory(_directory: &Path) -> io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inventory::Inventory;
    use crate::mission::run_file::{RunDocument, SavedEntry, SavedStep, RUN_FILE_VERSION};
    use crate::protocol::{
        CampaignDifficulty, CampaignRules, EquipmentPolicy, MissionId, WeaponType,
        CAMPAIGN_CONTINUES,
    };

    fn temp_dir() -> PathBuf {
        let path = std::env::temp_dir().join(format!("fragr-run-store-{}", Uuid::new_v4()));
        fs::create_dir(&path).unwrap();
        path
    }

    /// Distinct bundled content per stage; M01 keeps the fixture's [7; 32].
    fn hashes() -> ContentHashes {
        std::array::from_fn(|index| [7 + index as u8; 32])
    }

    fn document() -> RunDocument {
        RunDocument {
            version: RUN_FILE_VERSION,
            id: Uuid::new_v4(),
            starting_continues: CAMPAIGN_CONTINUES,
            remaining_continues: 2,
            level_start_continues: CAMPAIGN_CONTINUES,
            body: None,
            rules: CampaignRules::new(CampaignDifficulty::Standard),
            content_sha256: [7; 32],
            m03_outcome: None,
            m04_outcome: None,
            m05_outcome: None,
            m06_outcome: None,
            m08_outcome: None,
            m09_outcome: None,
            m10_transit: None,
            m11_outcome: None,
            m12_outcome: None,
            m13_outcome: None,
            m14_outcome: None,
            m15_outcome: None,
            m16_outcome: None,
            m17_outcome: None,
            m18_outcome: None,
            step: SavedStep::MissionEntry {
                mission: MissionId::RecallNotice,
                entry: SavedEntry {
                    hp: 100,
                    armor: 0,
                    equipment: Inventory::new(EquipmentPolicy::Discovery)
                        .saved_equipment(WeaponType::Fists)
                        .unwrap(),
                },
            },
        }
    }

    fn awaiting_m02() -> RunDocument {
        let mut awaiting = document();
        let SavedStep::MissionEntry { entry, .. } = awaiting.step else {
            panic!("expected entry")
        };
        awaiting.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::RecallNotice,
            next_mission: "persons_unknown".into(),
            exit: entry,
        };
        awaiting
    }

    fn probe(value: &serde_json::Value) -> RunProbe {
        RunStore::inspect_bytes(&serde_json::to_vec(value).unwrap(), hashes())
    }

    /// Only the live document and the writer lock remain after any write.
    fn directory_names(directory: &Path) -> Vec<String> {
        let mut names: Vec<_> = fs::read_dir(directory)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    #[test]
    fn current_document_round_trips_byte_for_byte_through_disk() {
        let directory = temp_dir();
        let store = RunStore::open_with_hashes(&directory, hashes()).unwrap();
        let original = document();
        store.save(&original).unwrap();
        let bytes = fs::read(directory.join(RUN_NAME)).unwrap();
        assert_eq!(bytes, serde_json::to_vec(&original).unwrap());
        let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(value["version"], RUN_FILE_VERSION);
        // Every equipment count is explicit; absence is never a default.
        let equipment = &value["step"]["entry"]["equipment"];
        for field in ["grenades", "proximity_mines", "remote_mines"] {
            assert_eq!(equipment[field], 0, "{field} must be written");
        }
        assert_eq!(store.load().unwrap(), Some(original.clone()));
        assert_eq!(
            RunStore::preview_with_hashes(&directory, hashes()).unwrap(),
            Some(original)
        );
        assert_eq!(directory_names(&directory), [RUN_NAME, LOCK_NAME]);
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn store_locks_one_writer_and_preserves_valid_save_on_pre_replace_failure() {
        let directory = temp_dir();
        let store = RunStore::open(&directory, [7; 32]).unwrap();
        let original = document();
        store.save(&original).unwrap();
        assert!(RunStore::open(&directory, [7; 32]).is_err());
        let mut updated = original.clone();
        updated.remaining_continues = 1;
        assert!(store
            .save_with_sync(
                &updated,
                |_| Err(io::Error::other("injected write failure")),
                sync_directory,
            )
            .is_err());
        assert_eq!(store.load().unwrap(), Some(original));
        assert_eq!(directory_names(&directory), [RUN_NAME, LOCK_NAME]);
        store.save(&updated).unwrap();
        assert_eq!(store.load().unwrap(), Some(updated));
        drop(store);
        // The lock is released with the store.
        RunStore::open(&directory, [7; 32]).unwrap();
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn post_rename_sync_failure_reports_the_live_save_as_uncertain() {
        let directory = temp_dir();
        let store = RunStore::open(&directory, [7; 32]).unwrap();
        let original = document();
        store.save(&original).unwrap();
        let mut updated = original.clone();
        updated.remaining_continues = 1;
        let error = store
            .save_with_sync(
                &updated,
                |_| Ok(()),
                |_| Err(io::Error::other("injected sync failure")),
            )
            .unwrap_err();
        assert!(error.to_string().contains("new campaign run is live"));
        assert_eq!(store.load().unwrap(), Some(updated));
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn save_refuses_an_invalid_document_without_touching_disk() {
        let directory = temp_dir();
        let store = RunStore::open_with_hashes(&directory, hashes()).unwrap();
        let original = document();
        store.save(&original).unwrap();
        let before = fs::read(directory.join(RUN_NAME)).unwrap();
        let mut wrong_content = original.clone();
        wrong_content.content_sha256 = [99; 32];
        let mut overspent = original.clone();
        overspent.remaining_continues = CAMPAIGN_CONTINUES + 1;
        let mut wrong_version = original;
        wrong_version.version = RUN_FILE_VERSION - 1;
        for bad in [wrong_content, overspent, wrong_version] {
            let error = store.save(&bad).unwrap_err();
            assert_eq!(error.kind(), io::ErrorKind::InvalidData);
            assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), before);
        }
        assert_eq!(directory_names(&directory), [RUN_NAME, LOCK_NAME]);
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn unreadable_bytes_are_corrupt_and_never_panic() {
        let current = serde_json::to_value(document()).unwrap();
        let oversized = vec![b' '; (MAX_RUN_BYTES + 1) as usize];
        for bytes in [
            &b""[..],
            b"not json",
            b"\xff\xfe\x00",
            b"[]",
            b"null",
            b"{}",
            b"{\"version\":\"23\"}",
            b"{\"version\":-1}",
            b"{\"version\":1.5}",
            &oversized,
        ] {
            assert!(
                matches!(RunStore::inspect_bytes(bytes, hashes()), RunProbe::Corrupt),
                "{:?}",
                String::from_utf8_lossy(&bytes[..bytes.len().min(32)])
            );
        }
        // The current version with a shape this build does not write is damage.
        let mut unknown = current.clone();
        unknown["extra"] = true.into();
        let mut missing = current.clone();
        missing["step"]["entry"]["equipment"]
            .as_object_mut()
            .unwrap()
            .remove("remote_mines");
        let mut null_outcome = current.clone();
        null_outcome["m03_outcome"] = serde_json::Value::Null;
        let mut bad_step = current.clone();
        bad_step["step"]["kind"] = "rewound".into();
        let mut bad_mission = current;
        bad_mission["step"]["mission"] = "planned_works".into();
        for value in [unknown, missing, null_outcome, bad_step, bad_mission] {
            assert!(matches!(probe(&value), RunProbe::Corrupt), "{value}");
        }
    }

    #[test]
    fn other_versions_changed_content_and_invalid_runs_are_incompatible() {
        let current = serde_json::to_value(document()).unwrap();
        for version in [0, 1, 2, 21, 22, u64::from(RUN_FILE_VERSION) + 1, u64::MAX] {
            if version == u64::from(RUN_FILE_VERSION) {
                continue;
            }
            // Old and future documents are refused before their shape is read,
            // whatever they contain.
            for body in [current.clone(), serde_json::json!({})] {
                let mut value = body;
                value["version"] = version.into();
                assert!(
                    matches!(probe(&value), RunProbe::Incompatible),
                    "version {version}"
                );
            }
        }
        let mut changed_content = current.clone();
        changed_content["content_sha256"] = serde_json::to_value([8_u8; 32]).unwrap();
        let mut overspent = current.clone();
        overspent["remaining_continues"] = (CAMPAIGN_CONTINUES + 1).into();
        let mut old_rules = current.clone();
        old_rules["rules"]["revision"] = 3.into();
        let mut nil_id = current.clone();
        nil_id["id"] = Uuid::nil().to_string().into();
        let mut forged_sniper = current;
        forged_sniper["step"]["entry"]["equipment"]["weapons"]
            .as_array_mut()
            .unwrap()
            .push("sniper".into());
        for value in [changed_content, overspent, old_rules, nil_id, forged_sniper] {
            assert!(matches!(probe(&value), RunProbe::Incompatible), "{value}");
        }
    }

    #[test]
    fn load_reports_refusals_as_invalid_data_with_a_reason() {
        let directory = temp_dir();
        let store = RunStore::open_with_hashes(&directory, hashes()).unwrap();
        assert!(store.load().unwrap().is_none());
        assert!(matches!(
            RunStore::inspect_with_hashes(&directory, hashes()).unwrap(),
            RunProbe::Missing
        ));
        fs::write(directory.join(RUN_NAME), b"not json").unwrap();
        let error = store.load().unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
        assert!(error.to_string().contains("invalid campaign run"));
        let mut old = serde_json::to_value(document()).unwrap();
        old["version"] = (RUN_FILE_VERSION - 1).into();
        fs::write(directory.join(RUN_NAME), serde_json::to_vec(&old).unwrap()).unwrap();
        let error = store.load().unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
        assert!(error.to_string().contains("incompatible campaign run"));
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn new_run_replaces_any_prior_file_without_leaving_copies() {
        let mut old = serde_json::to_value(document()).unwrap();
        old["version"] = (RUN_FILE_VERSION - 1).into();
        let mut future = old.clone();
        future["version"] = (RUN_FILE_VERSION + 1).into();
        for prior in [
            b"older unsupported bytes".to_vec(),
            serde_json::to_vec(&old).unwrap(),
            serde_json::to_vec(&future).unwrap(),
            serde_json::to_vec(&document()).unwrap(),
        ] {
            let directory = temp_dir();
            let store = RunStore::open_with_hashes(&directory, hashes()).unwrap();
            fs::write(directory.join(RUN_NAME), &prior).unwrap();
            let created = document();
            store.save(&created).unwrap();
            assert_eq!(store.load().unwrap(), Some(created));
            assert_eq!(directory_names(&directory), [RUN_NAME, LOCK_NAME]);
            drop(store);
            fs::remove_dir_all(directory).unwrap();
        }
    }

    #[test]
    fn promotion_is_one_atomic_replace_and_a_failed_write_keeps_the_source() {
        let directory = temp_dir();
        let store = RunStore::open_with_hashes(&directory, hashes()).unwrap();
        let awaiting = awaiting_m02();
        store.save(&awaiting).unwrap();
        let source = fs::read(directory.join(RUN_NAME)).unwrap();
        let promoted = awaiting.promote_m02(hashes()[1]).unwrap();
        assert_eq!(promoted.version, RUN_FILE_VERSION);
        assert_eq!(promoted.stage_mission(), MissionId::PersonsUnknown);
        assert_eq!(
            (promoted.remaining_continues, promoted.level_start_continues),
            (2, 2)
        );
        assert_eq!(promoted.attempt(), 1);
        let error = store
            .save_with_sync(
                &promoted,
                |_| Err(io::Error::other("injected replacement failure")),
                sync_directory,
            )
            .unwrap_err();
        assert!(error.to_string().contains("injected replacement failure"));
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), source);
        assert_eq!(store.load().unwrap(), Some(awaiting.clone()));
        store.save(&promoted).unwrap();
        assert_eq!(store.load().unwrap(), Some(promoted.clone()));
        assert_eq!(directory_names(&directory), [RUN_NAME, LOCK_NAME]);
        // A promoted entry is not promotable again, and an awaiting run is
        // bound to the mission its edge names.
        assert!(promoted.promote_m02(hashes()[1]).is_err());
        assert!(awaiting
            .promote_next(MissionId::ScheduledService, hashes()[2])
            .is_err());
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }
}

#[cfg(test)]
mod arc_tests;
#[cfg(test)]
mod late_campaign_tests;
#[cfg(test)]
mod m06_tests;
#[cfg(test)]
mod m07_tests;
#[cfg(test)]
mod m08_tests;
#[cfg(test)]
mod m09_receipt_tests;
#[cfg(test)]
mod m09_tests;
#[cfg(test)]
mod m10_tests;
#[cfg(test)]
mod m11_tests;
#[cfg(test)]
mod m12_tests;
#[cfg(test)]
mod m13_tests;
#[cfg(test)]
mod m14_tests;
#[cfg(test)]
pub(super) mod m15_tests;
#[cfg(test)]
mod stair_entry_tests;
