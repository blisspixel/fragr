//! Bounded local run storage. The lock file is never renamed with the save.
use super::{RunDocument, RunDocumentV2};
use crate::protocol::MissionId;
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use uuid::Uuid;

const MAX_RUN_BYTES: u64 = 65_536;
const RUN_NAME: &str = "run.json";
const LOCK_NAME: &str = "run.lock";

pub(crate) struct RunStore {
    directory: PathBuf,
    m01_hash: [u8; 32],
    m02_hash: [u8; 32],
    _lock: File,
}

pub(crate) enum RunProbe {
    Missing,
    Compatible(RunDocument),
    Incompatible,
    Corrupt,
}

impl RunStore {
    /// Only the local child opens a writable run. Tests supply an isolated dir.
    #[cfg(test)]
    pub fn open(directory: &Path, content_sha256: [u8; 32]) -> io::Result<Self> {
        Self::open_with_hashes(directory, content_sha256, content_sha256)
    }

    pub fn open_with_hashes(
        directory: &Path,
        m01_hash: [u8; 32],
        m02_hash: [u8; 32],
    ) -> io::Result<Self> {
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
            m01_hash,
            m02_hash,
            _lock: lock,
        })
    }

    pub fn load(&self) -> io::Result<Option<RunDocument>> {
        Self::preview_with_hashes(&self.directory, self.m01_hash, self.m02_hash)
    }

    /// A menu may inspect an unlocked snapshot. Launch always reopens under
    /// the writer lock and validates again before advertising readiness.
    #[cfg(test)]
    pub fn preview(directory: &Path, content_sha256: [u8; 32]) -> io::Result<Option<RunDocument>> {
        Self::preview_with_hashes(directory, content_sha256, content_sha256)
    }

    pub fn preview_with_hashes(
        directory: &Path,
        m01_hash: [u8; 32],
        m02_hash: [u8; 32],
    ) -> io::Result<Option<RunDocument>> {
        match Self::inspect_with_hashes(directory, m01_hash, m02_hash)? {
            RunProbe::Missing => Ok(None),
            RunProbe::Compatible(document) => Ok(Some(document)),
            RunProbe::Incompatible => Err(invalid("incompatible campaign run document")),
            RunProbe::Corrupt => Err(invalid("invalid campaign run document")),
        }
    }

    #[cfg(test)]
    pub fn inspect(directory: &Path, content_sha256: [u8; 32]) -> io::Result<RunProbe> {
        Self::inspect_with_hashes(directory, content_sha256, content_sha256)
    }

    pub fn inspect_with_hashes(
        directory: &Path,
        m01_hash: [u8; 32],
        m02_hash: [u8; 32],
    ) -> io::Result<RunProbe> {
        let file = match File::open(directory.join(RUN_NAME)) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(RunProbe::Missing),
            Err(error) => return Err(error),
        };
        let mut bytes = Vec::new();
        file.take(MAX_RUN_BYTES + 1).read_to_end(&mut bytes)?;
        Ok(Self::inspect_bytes(&bytes, m01_hash, m02_hash))
    }

    fn inspect_bytes(bytes: &[u8], m01_hash: [u8; 32], m02_hash: [u8; 32]) -> RunProbe {
        if bytes.len() as u64 > MAX_RUN_BYTES {
            return RunProbe::Corrupt;
        }
        let Ok(value) = serde_json::from_slice::<serde_json::Value>(bytes) else {
            return RunProbe::Corrupt;
        };
        // A readable document of another format version is a real run this
        // build cannot continue, not damage. New Run archives its bytes.
        let version = value.get("version").and_then(serde_json::Value::as_u64);
        let document = match version {
            Some(2) => {
                let legacy: RunDocumentV2 = match serde_json::from_value(value) {
                    Ok(document) => document,
                    Err(_) => return RunProbe::Corrupt,
                };
                match legacy.upgrade(m01_hash) {
                    Ok(document) => document,
                    Err(_) => return RunProbe::Incompatible,
                }
            }
            Some(version) if version == u64::from(super::RUN_FILE_VERSION) => {
                match serde_json::from_value::<RunDocument>(value) {
                    Ok(document) => document,
                    Err(_) => return RunProbe::Corrupt,
                }
            }
            Some(_) => return RunProbe::Incompatible,
            None => return RunProbe::Corrupt,
        };
        let expected = match document.stage_mission() {
            MissionId::RecallNotice => m01_hash,
            MissionId::PersonsUnknown => m02_hash,
        };
        if document.validate(expected).is_err() {
            return RunProbe::Incompatible;
        }
        RunProbe::Compatible(document)
    }

    pub fn needs_upgrade(&self) -> io::Result<bool> {
        let mut bytes = Vec::new();
        File::open(self.directory.join(RUN_NAME))?
            .take(MAX_RUN_BYTES + 1)
            .read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_RUN_BYTES {
            return Err(invalid("campaign run exceeds size limit"));
        }
        let value: serde_json::Value = serde_json::from_slice(&bytes)?;
        Ok(value.get("version").and_then(serde_json::Value::as_u64) == Some(2))
    }

    /// Archive source bytes without removing run.json, then atomically replace
    /// it. A pre-replace failure leaves the old document at its normal path.
    pub fn archive_and_save(
        &self,
        source_document: &RunDocument,
        document: &RunDocument,
    ) -> io::Result<PathBuf> {
        self.archive_and_save_before_replace(source_document, document, |_| Ok(()))
    }

    fn archive_and_save_before_replace(
        &self,
        source_document: &RunDocument,
        document: &RunDocument,
        before_replace: impl FnOnce(&Path) -> io::Result<()>,
    ) -> io::Result<PathBuf> {
        document
            .validate(self.expected_hash(document))
            .map_err(invalid)?;
        let source = read_bounded(&self.directory.join(RUN_NAME))?;
        if !matches!(
            Self::inspect_bytes(&source, self.m01_hash, self.m02_hash),
            RunProbe::Compatible(current) if current == *source_document
        ) {
            return Err(invalid("campaign run changed before migration"));
        }
        // The source may still be run.json after a failed replacement. Its
        // content address makes migration retries reuse the same archive.
        let digest: String = Sha256::digest(&source)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect();
        let archive = self.directory.join(format!("run.prior-{digest}.json"));
        if archive.exists() {
            if read_bounded(&archive)? != source {
                return Err(invalid("campaign run archive differs from source"));
            }
        } else {
            let temporary = self
                .directory
                .join(format!(".run-archive-{}.tmp", Uuid::new_v4().simple()));
            let result = (|| {
                let mut file = OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&temporary)?;
                file.write_all(&source)?;
                file.sync_all()?;
                drop(file);
                fs::rename(&temporary, &archive)
            })();
            if let Err(error) = result {
                let _ = fs::remove_file(&temporary);
                return Err(error);
            }
        }
        sync_directory(&self.directory)?;
        self.save_before_replace(document, |temporary| {
            before_replace(temporary)?;
            if read_bounded(&self.directory.join(RUN_NAME))? != source {
                return Err(invalid("campaign run changed before replacement"));
            }
            Ok(())
        })?;
        Ok(archive)
    }

    fn expected_hash(&self, document: &RunDocument) -> [u8; 32] {
        match document.stage_mission() {
            MissionId::RecallNotice => self.m01_hash,
            MissionId::PersonsUnknown => self.m02_hash,
        }
    }

    pub fn save(&self, document: &RunDocument) -> io::Result<()> {
        self.save_before_replace(document, |_| Ok(()))
    }

    /// Explicit New Run keeps the previous bytes recoverable under the same
    /// writer lock, including a document this version cannot decode.
    pub fn start_new(&self, document: &RunDocument) -> io::Result<Option<PathBuf>> {
        self.start_new_with_sync(document, sync_directory)
    }

    fn start_new_with_sync(
        &self,
        document: &RunDocument,
        sync: impl Fn(&Path) -> io::Result<()>,
    ) -> io::Result<Option<PathBuf>> {
        document
            .validate(self.expected_hash(document))
            .map_err(invalid)?;
        let prior = self.directory.join(RUN_NAME);
        let archived = if prior.try_exists()? {
            let archive = self
                .directory
                .join(format!("run.prior-{}.json", Uuid::new_v4().simple()));
            fs::rename(&prior, &archive)?;
            if let Err(error) = sync(&self.directory) {
                let moved = archive.try_exists()? && !prior.try_exists()?;
                return Err(io::Error::new(
                    error.kind(),
                    if moved {
                        format!("prior campaign run is archived; directory durability is uncertain: {error}")
                    } else {
                        format!("prior campaign run archive location is uncertain: {error}")
                    },
                ));
            }
            Some(archive)
        } else {
            None
        };
        self.save(document)?;
        Ok(archived)
    }

    fn save_before_replace(
        &self,
        document: &RunDocument,
        before_replace: impl FnOnce(&Path) -> io::Result<()>,
    ) -> io::Result<()> {
        self.save_with_sync(document, before_replace, sync_directory)
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

fn read_bounded(path: &Path) -> io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    File::open(path)?
        .take(MAX_RUN_BYTES + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_RUN_BYTES {
        return Err(invalid("campaign run exceeds size limit"));
    }
    Ok(bytes)
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
            .save_before_replace(&updated, |_| Err(io::Error::other(
                "injected write failure"
            )))
            .is_err());
        assert_eq!(store.load().unwrap(), Some(original));
        store.save(&updated).unwrap();
        assert_eq!(store.load().unwrap(), Some(updated));
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn store_bounds_and_validates_untrusted_run_bytes() {
        let directory = temp_dir();
        let store = RunStore::open(&directory, [7; 32]).unwrap();
        assert!(store.load().unwrap().is_none());
        fs::write(directory.join(RUN_NAME), b"not json").unwrap();
        assert_eq!(store.load().unwrap_err().kind(), io::ErrorKind::InvalidData);
        fs::write(
            directory.join(RUN_NAME),
            vec![b' '; (MAX_RUN_BYTES + 1) as usize],
        )
        .unwrap();
        assert_eq!(store.load().unwrap_err().kind(), io::ErrorKind::InvalidData);
        let mut mismatched = document();
        mismatched.content_sha256 = [8; 32];
        fs::write(
            directory.join(RUN_NAME),
            serde_json::to_vec(&mismatched).unwrap(),
        )
        .unwrap();
        assert_eq!(store.load().unwrap_err().kind(), io::ErrorKind::InvalidData);
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn explicit_new_run_archives_even_an_incompatible_prior() {
        let directory = temp_dir();
        let store = RunStore::open(&directory, [7; 32]).unwrap();
        fs::write(directory.join(RUN_NAME), b"older unsupported bytes").unwrap();
        let created = document();
        let archive = store.start_new(&created).unwrap().unwrap();
        assert_eq!(fs::read(&archive).unwrap(), b"older unsupported bytes");
        assert_eq!(store.load().unwrap(), Some(created));
        assert_eq!(
            RunStore::preview(&directory, [7; 32]).unwrap(),
            store.load().unwrap()
        );
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn changed_m02_map_hash_requires_new_run_and_archives_the_prior_bytes() {
        let directory = temp_dir();
        let store = RunStore::open_with_hashes(&directory, [7; 32], [9; 32]).unwrap();
        let mut prior = document();
        prior.step = SavedStep::MissionEntry {
            mission: MissionId::PersonsUnknown,
            entry: SavedEntry {
                hp: 100,
                armor: 0,
                equipment: Inventory::new(EquipmentPolicy::Discovery)
                    .saved_equipment(WeaponType::Fists)
                    .unwrap(),
            },
        };
        prior.content_sha256 = [8; 32];
        let bytes = serde_json::to_vec(&prior).unwrap();
        fs::write(directory.join(RUN_NAME), &bytes).unwrap();
        assert!(matches!(
            RunStore::inspect_with_hashes(&directory, [7; 32], [9; 32]).unwrap(),
            RunProbe::Incompatible
        ));
        let mut current = prior;
        current.content_sha256 = [9; 32];
        let archive = store.start_new(&current).unwrap().unwrap();
        assert_eq!(fs::read(archive).unwrap(), bytes);
        assert_eq!(store.load().unwrap(), Some(current));
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    /// A save written before magazines were removed is a real run this build
    /// cannot continue: it reads as incompatible, never corrupt, and New Run
    /// keeps its exact bytes.
    #[test]
    fn magazine_era_run_needs_a_new_run_and_keeps_its_bytes() {
        let directory = temp_dir();
        let store = RunStore::open(&directory, [7; 32]).unwrap();
        let hash = [7_u8; 32];
        let legacy = serde_json::json!({
            "version": 1,
            "id": Uuid::from_u128(9),
            "starting_continues": CAMPAIGN_CONTINUES,
            "remaining_continues": 2,
            "rules": {"difficulty": "standard", "revision": 1},
            "content_sha256": hash,
            "step": {"kind": "mission_entry", "mission": "recall_notice", "entry": {
                "hp": 100, "armor": 0, "equipment": {
                    "selected": "tack",
                    "weapons": [{"weapon": "fists", "magazine": null}, {"weapon": "tack", "magazine": 11}],
                    "reserves": [{"pool": "tacks", "rounds": 36}, {"pool": "darts", "rounds": 0}, {"pool": "cores", "rounds": 0}],
                    "personal_claims": ["bay_tack"]
                }
            }}
        });
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(directory.join(RUN_NAME), &bytes).unwrap();
        assert!(matches!(
            RunStore::inspect(&directory, [7; 32]).unwrap(),
            RunProbe::Incompatible
        ));
        assert!(store
            .load()
            .unwrap_err()
            .to_string()
            .contains("incompatible"));
        // The same shape claiming the current version is damage, not an old run.
        let mut forged = legacy.clone();
        forged["version"] = RUN_FILE_VERSION.into();
        fs::write(
            directory.join(RUN_NAME),
            serde_json::to_vec(&forged).unwrap(),
        )
        .unwrap();
        assert!(matches!(
            RunStore::inspect(&directory, [7; 32]).unwrap(),
            RunProbe::Corrupt
        ));
        fs::write(directory.join(RUN_NAME), &bytes).unwrap();
        let created = document();
        let archive = store.start_new(&created).unwrap().unwrap();
        assert_eq!(fs::read(&archive).unwrap(), bytes);
        assert_eq!(store.load().unwrap(), Some(created));
        drop(store);
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
    fn archive_sync_failure_keeps_prior_bytes_recoverable() {
        let directory = temp_dir();
        let store = RunStore::open(&directory, [7; 32]).unwrap();
        let original = document();
        store.save(&original).unwrap();
        let error = store
            .start_new_with_sync(&document(), |_| {
                Err(io::Error::other("injected sync failure"))
            })
            .unwrap_err();
        assert!(error.to_string().contains("prior campaign run is archived"));
        let archives: Vec<_> = fs::read_dir(&directory)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| {
                entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with("run.prior-")
            })
            .collect();
        assert_eq!(archives.len(), 1);
        assert_eq!(
            fs::read(archives[0].path()).unwrap(),
            serde_json::to_vec(&original).unwrap()
        );
        assert!(store.load().unwrap().is_none());
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn v2_m01_departure_is_readable_and_archived_before_m02_promotion() {
        let directory = temp_dir();
        let store = RunStore::open_with_hashes(&directory, [7; 32], [8; 32]).unwrap();
        let mut legacy = serde_json::to_value(document()).unwrap();
        legacy["version"] = 2.into();
        legacy
            .as_object_mut()
            .unwrap()
            .remove("level_start_continues");
        legacy.as_object_mut().unwrap().remove("body");
        legacy["step"] = serde_json::json!({
            "kind": "awaiting_mission", "completed_mission": "recall_notice",
            "next_mission": "persons_unknown", "exit": {
                "hp": 61, "armor": 7,
                "equipment": Inventory::new(EquipmentPolicy::Discovery)
                    .saved_equipment(WeaponType::Fists).unwrap()
            }
        });
        let source = serde_json::to_vec(&legacy).unwrap();
        fs::write(directory.join(RUN_NAME), &source).unwrap();
        let loaded = store.load().unwrap().unwrap();
        assert_eq!(loaded.version, RUN_FILE_VERSION);
        assert_eq!(loaded.level_start_continues, CAMPAIGN_CONTINUES);
        assert_eq!(loaded.body, None);
        assert!(store.needs_upgrade().unwrap());
        let promoted = loaded.promote_m02([8; 32]).unwrap();
        assert_eq!(promoted.remaining_continues, 2);
        assert_eq!(promoted.level_start_continues, 2);
        assert_eq!(promoted.attempt(), 1);
        let archive = store.archive_and_save(&loaded, &promoted).unwrap();
        assert_eq!(fs::read(archive).unwrap(), source);
        assert_eq!(store.load().unwrap(), Some(promoted));
        assert!(!store.needs_upgrade().unwrap());
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn promotion_write_failure_keeps_original_run_and_an_exact_archive() {
        let directory = temp_dir();
        let store = RunStore::open_with_hashes(&directory, [7; 32], [8; 32]).unwrap();
        let mut awaiting = document();
        let SavedStep::MissionEntry { entry, .. } = awaiting.step else {
            panic!("expected entry")
        };
        awaiting.step = SavedStep::AwaitingMission {
            completed_mission: MissionId::RecallNotice,
            next_mission: "persons_unknown".into(),
            exit: entry,
        };
        store.save(&awaiting).unwrap();
        let source = fs::read(directory.join(RUN_NAME)).unwrap();
        let promoted = awaiting.promote_m02([8; 32]).unwrap();
        let error = store
            .archive_and_save_before_replace(&awaiting, &promoted, |_| {
                Err(io::Error::other("injected replacement failure"))
            })
            .unwrap_err();
        assert!(error.to_string().contains("injected replacement failure"));
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), source);
        let archives: Vec<_> = fs::read_dir(&directory)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| {
                entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with("run.prior-")
            })
            .collect();
        assert_eq!(archives.len(), 1);
        assert_eq!(fs::read(archives[0].path()).unwrap(), source);
        assert_eq!(store.load().unwrap(), Some(awaiting.clone()));
        let retried = store.archive_and_save(&awaiting, &promoted).unwrap();
        assert_eq!(retried, archives[0].path());
        assert_eq!(store.load().unwrap(), Some(promoted));
        let archive_count = fs::read_dir(&directory)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| {
                entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with("run.prior-")
            })
            .count();
        assert_eq!(archive_count, 1);
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn invalid_migration_target_does_not_archive_source() {
        let directory = temp_dir();
        let store = RunStore::open(&directory, [7; 32]).unwrap();
        let original = document();
        store.save(&original).unwrap();
        let source = fs::read(directory.join(RUN_NAME)).unwrap();
        let mut invalid_target = original.clone();
        invalid_target.content_sha256 = [9; 32];
        assert!(store.archive_and_save(&original, &invalid_target).is_err());
        assert_eq!(fs::read(directory.join(RUN_NAME)).unwrap(), source);
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 2);
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn migration_refuses_oversized_or_changed_source() {
        let directory = temp_dir();
        let store = RunStore::open(&directory, [7; 32]).unwrap();
        let original = document();
        let mut target = original.clone();
        target.remaining_continues = 1;
        let path = directory.join(RUN_NAME);
        fs::write(&path, vec![b' '; MAX_RUN_BYTES as usize + 1]).unwrap();
        assert!(store.archive_and_save(&original, &target).is_err());
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 2);

        store.save(&original).unwrap();
        let mut changed = original.clone();
        changed.remaining_continues = 0;
        let changed_bytes = serde_json::to_vec(&changed).unwrap();
        fs::write(&path, &changed_bytes).unwrap();
        assert!(store.archive_and_save(&original, &target).is_err());
        assert_eq!(fs::read(&path).unwrap(), changed_bytes);
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 2);

        store.save(&original).unwrap();
        let error = store
            .archive_and_save_before_replace(&original, &target, |_| {
                fs::write(&path, &changed_bytes)
            })
            .unwrap_err();
        assert!(error.to_string().contains("changed before replacement"));
        assert_eq!(fs::read(&path).unwrap(), changed_bytes);
        assert_eq!(store.load().unwrap(), Some(changed));
        drop(store);
        fs::remove_dir_all(directory).unwrap();
    }
}
