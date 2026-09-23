//! Bounded local run storage. The lock file is never renamed with the save.
use super::RunDocument;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use uuid::Uuid;

const MAX_RUN_BYTES: u64 = 65_536;
const RUN_NAME: &str = "run.json";
const LOCK_NAME: &str = "run.lock";

pub(crate) struct RunStore {
    directory: PathBuf,
    content_sha256: [u8; 32],
    _lock: File,
}

impl RunStore {
    /// Only the local child opens a writable run. Tests supply an isolated dir.
    pub fn open(directory: &Path, content_sha256: [u8; 32]) -> io::Result<Self> {
        fs::create_dir_all(directory)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .open(directory.join(LOCK_NAME))?;
        lock.try_lock()?;
        Ok(Self {
            directory: directory.to_owned(),
            content_sha256,
            _lock: lock,
        })
    }

    pub fn load(&self) -> io::Result<Option<RunDocument>> {
        let file = match File::open(self.directory.join(RUN_NAME)) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        };
        let mut bytes = Vec::new();
        file.take(MAX_RUN_BYTES + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_RUN_BYTES {
            return Err(invalid("campaign run document exceeds the size limit"));
        }
        let document: RunDocument =
            serde_json::from_slice(&bytes).map_err(|_| invalid("invalid campaign run document"))?;
        document.validate(self.content_sha256).map_err(invalid)?;
        Ok(Some(document))
    }

    pub fn save(&self, document: &RunDocument) -> io::Result<()> {
        self.save_before_replace(document, |_| Ok(()))
    }

    fn save_before_replace(
        &self,
        document: &RunDocument,
        before_replace: impl FnOnce(&Path) -> io::Result<()>,
    ) -> io::Result<()> {
        document.validate(self.content_sha256).map_err(invalid)?;
        let bytes = serde_json::to_vec(document)
            .map_err(|_| invalid("campaign run document could not be encoded"))?;
        if bytes.len() as u64 > MAX_RUN_BYTES {
            return Err(invalid("campaign run document exceeds the size limit"));
        }
        let temporary = self
            .directory
            .join(format!("run.{}.tmp", Uuid::new_v4().simple()));
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
            sync_directory(&self.directory)
        })();
        if result.is_err() {
            // A failed rename leaves only this unique temporary file. After
            // rename, the path no longer exists and the new run may be live.
            let _ = fs::remove_file(&temporary);
        }
        result
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

    fn document() -> RunDocument {
        RunDocument {
            version: RUN_FILE_VERSION,
            id: Uuid::new_v4(),
            starting_continues: CAMPAIGN_CONTINUES,
            remaining_continues: 2,
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
}
