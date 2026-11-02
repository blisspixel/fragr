//! Where fun metrics live and how they die: one file per match under the
//! host's run directory, shredded once it is older than 67 days. Nothing
//! here sends anything anywhere.
use super::record::{FunRecord, RECORD_SCHEMA};
use super::RETENTION_DAYS;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// The folder under the run directory (`LOCALEXCEPTION_RUN_DIR` or the platform's
/// user data folder) that holds every record.
pub const DIRECTORY: &str = "fun-metrics";
const PREFIX: &str = "match-";
const SUFFIX: &str = ".json";
const PARTIAL: &str = ".json.part";
/// How often a running server shreds.
pub const SHRED_EVERY: Duration = Duration::from_secs(24 * 60 * 60);
/// The most records one day's folder takes before a write is refused.
const DAILY_LIMIT: u32 = 10_000;

pub fn retention() -> Duration {
    Duration::from_secs(RETENTION_DAYS * 24 * 60 * 60)
}

/// What one pass of the shredder did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Shredding {
    pub shredded: u32,
    pub kept: u32,
}

impl Shredding {
    /// The log line, in the house voice.
    pub fn line(&self) -> String {
        match self.shredded {
            0 => format!(
                "Fun metrics: {} match tallies on file, none past {RETENTION_DAYS} days. Nothing to shred.",
                self.kept
            ),
            1 => format!(
                "Fun metrics: shredded 1 match tally older than {RETENTION_DAYS} days. The Union would have kept it forever."
            ),
            count => format!(
                "Fun metrics: shredded {count} match tallies older than {RETENTION_DAYS} days. The Union would have kept them forever."
            ),
        }
    }
}

/// Year, month and day of a count of days since 1970-01-01, proleptic
/// Gregorian (Howard Hinnant's `civil_from_days`).
fn civil(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (yoe + era * 400 + i64::from(month <= 2), month, day)
}

fn day_stamp(now: SystemTime) -> String {
    let days = now
        .duration_since(UNIX_EPOCH)
        .map_or(0, |since| since.as_secs() / 86_400);
    let (year, month, day) = civil(i64::try_from(days).unwrap_or(0));
    format!("{year:04}-{month:02}-{day:02}")
}

/// A file this store wrote, finished or interrupted.
fn ours(name: &str) -> bool {
    name.starts_with(PREFIX) && (name.ends_with(SUFFIX) || name.ends_with(PARTIAL))
}

/// One host's folder of records.
#[derive(Debug, Clone)]
pub struct FunStore {
    dir: PathBuf,
}

impl FunStore {
    /// The folder, created if it is missing.
    pub fn open(dir: impl Into<PathBuf>) -> io::Result<Self> {
        let dir = dir.into();
        std::fs::create_dir_all(&dir)?;
        Ok(Self { dir })
    }

    /// The host's own folder under its run directory, made if missing.
    pub fn for_host() -> io::Result<Self> {
        Self::open(Self::host_dir()?)
    }

    /// Where the host's folder is, without making it: a reader names the
    /// folder and never creates one.
    pub fn host_dir() -> io::Result<PathBuf> {
        Ok(crate::local::run_directory()?.join(DIRECTORY))
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// File one match: `match-YYYY-MM-DD-NNNN.json`, the day only, never
    /// the time of day. Written beside the name and renamed into it, so a
    /// reader never sees half a record.
    pub fn write(&self, record: &FunRecord, now: SystemTime) -> io::Result<PathBuf> {
        let json = serde_json::to_vec_pretty(record)?;
        let day = day_stamp(now);
        for number in 1..=DAILY_LIMIT {
            let name = format!("{PREFIX}{day}-{number:04}");
            let done = self.dir.join(format!("{name}{SUFFIX}"));
            let partial = self.dir.join(format!("{name}{PARTIAL}"));
            if done.exists() {
                continue;
            }
            let mut file = match std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&partial)
            {
                Ok(file) => file,
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            };
            file.write_all(&json)?;
            file.write_all(b"\n")?;
            file.sync_all()?;
            drop(file);
            std::fs::rename(&partial, &done)?;
            return Ok(done);
        }
        Err(io::Error::other(format!(
            "{DAILY_LIMIT} match tallies already filed today"
        )))
    }

    /// Delete every record older than the retention window by its file
    /// time. Only this store's own files are touched.
    pub fn shred(&self, now: SystemTime) -> io::Result<Shredding> {
        let mut result = Shredding::default();
        for entry in std::fs::read_dir(&self.dir)? {
            let entry = entry?;
            let name = entry.file_name();
            let Some(name) = name.to_str() else { continue };
            if !ours(name) || !entry.file_type()?.is_file() {
                continue;
            }
            let modified = entry.metadata()?.modified()?;
            // A file from the future is a clock that moved; it is judged
            // again once the clock catches up.
            let age = now.duration_since(modified).unwrap_or_default();
            if age > retention() {
                std::fs::remove_file(entry.path())?;
                result.shredded += 1;
            } else {
                result.kept += 1;
            }
        }
        Ok(result)
    }

    /// Every finished record in the folder, oldest name first, and a line
    /// for each file that is not one.
    pub fn read_all(dir: &Path) -> io::Result<(Vec<FunRecord>, Vec<String>)> {
        let mut names: Vec<PathBuf> = std::fs::read_dir(dir)?
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.starts_with(PREFIX) && name.ends_with(SUFFIX))
            })
            .collect();
        names.sort();
        let mut records = Vec::new();
        let mut refused = Vec::new();
        for path in names {
            let text = match std::fs::read_to_string(&path) {
                Ok(text) => text,
                Err(error) => {
                    refused.push(format!("{}: {error}", path.display()));
                    continue;
                }
            };
            match serde_json::from_str::<FunRecord>(&text) {
                Ok(record) if record.schema == RECORD_SCHEMA => records.push(record),
                Ok(record) => refused.push(format!(
                    "{}: schema {} is not the current {RECORD_SCHEMA}; delete it or let the shredder have it",
                    path.display(),
                    record.schema
                )),
                Err(error) => refused.push(format!("{}: {error}", path.display())),
            }
        }
        Ok((records, refused))
    }
}

/// When the next shred is due: at start, then every day of wall time. A
/// clock that steps backwards shreds at once rather than waiting a day
/// from a time that never came.
#[derive(Debug, Clone, Copy, Default)]
pub struct ShredClock {
    last: Option<SystemTime>,
}

impl ShredClock {
    pub fn due(&self, now: SystemTime) -> bool {
        match self.last {
            None => true,
            Some(last) => now
                .duration_since(last)
                .map_or(true, |since| since >= SHRED_EVERY),
        }
    }

    pub fn ran(&mut self, now: SystemTime) {
        self.last = Some(now);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fun_metrics::record::{FunRecord, MatchTally};
    use crate::protocol::GameMode;

    fn scratch(label: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "localexception-fun-{label}-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn record() -> FunRecord {
        FunRecord {
            schema: RECORD_SCHEMA,
            map_id: 1,
            mode: GameMode::Ffa,
            mutators: Vec::new(),
            friendly_fire: false,
            bot_tier: crate::sim::BotSkill::Regular,
            finished: true,
            match_ticks: 1200,
            fighters_peak: 4,
            bots_peak: 4,
            tally: MatchTally {
                frags: 9,
                live_ticks: 1200,
                ..MatchTally::default()
            },
            tick_health: None,
        }
    }

    const DAY: Duration = Duration::from_secs(86_400);

    #[test]
    fn the_civil_calendar_names_days() {
        assert_eq!(civil(0), (1970, 1, 1));
        assert_eq!(civil(19_723), (2024, 1, 1));
        assert_eq!(civil(20_758), (2026, 11, 1));
        assert_eq!(civil(11_016), (2000, 2, 29));
        assert_eq!(
            day_stamp(UNIX_EPOCH + Duration::from_secs(20_758 * 86_400 + 86_399)),
            "2026-11-01"
        );
    }

    #[test]
    fn a_match_is_one_file_named_by_day_and_read_back() {
        let dir = scratch("write");
        let store = FunStore::open(&dir).unwrap();
        let now = UNIX_EPOCH + 20_758 * DAY + Duration::from_secs(3600 * 13 + 17);
        let first = store.write(&record(), now).unwrap();
        let second = store.write(&record(), now).unwrap();
        assert_eq!(
            first.file_name().unwrap().to_str().unwrap(),
            "match-2026-11-01-0001.json"
        );
        assert_eq!(
            second.file_name().unwrap().to_str().unwrap(),
            "match-2026-11-01-0002.json"
        );
        std::fs::write(dir.join("notes.txt"), "the host's own file").unwrap();
        std::fs::write(dir.join("match-2026-11-01-0003.json"), "{\"schema\":0}").unwrap();
        let (records, refused) = FunStore::read_all(&dir).unwrap();
        assert_eq!(records, vec![record(), record()]);
        assert_eq!(refused.len(), 1, "{refused:?}");
        let mut old = record();
        old.schema = 0;
        std::fs::write(
            dir.join("match-2026-11-01-0004.json"),
            serde_json::to_string(&old).unwrap(),
        )
        .unwrap();
        let (_, refused) = FunStore::read_all(&dir).unwrap();
        assert!(refused[1].contains("is not the current"), "{refused:?}");
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn files_past_sixty_seven_days_are_shredded_and_nothing_else_is() {
        let dir = scratch("shred");
        let store = FunStore::open(&dir).unwrap();
        let now = UNIX_EPOCH + 20_758 * DAY;
        let aged = |name: &str, days_old: u64| {
            let path = dir.join(name);
            std::fs::write(&path, "{}").unwrap();
            let file = std::fs::File::options().write(true).open(&path).unwrap();
            file.set_modified(now - Duration::from_secs(86_400 * days_old))
                .unwrap();
        };
        aged("match-2026-08-01-0001.json", 92);
        aged("match-2026-08-25-0001.json", 68);
        aged("match-2026-08-25-0002.json.part", 68);
        aged("match-2026-08-27-0001.json", 66);
        aged("match-2026-10-31-0001.json", 1);
        // Not ours, however old: the shredder never touches it.
        aged("head-to-head.json", 400);
        aged("match-notes.txt", 400);
        let pass = store.shred(now).unwrap();
        assert_eq!(
            pass,
            Shredding {
                shredded: 3,
                kept: 2
            }
        );
        assert!(pass
            .line()
            .contains("shredded 3 match tallies older than 67 days"));
        assert!(pass
            .line()
            .contains("The Union would have kept them forever."));
        let mut left: Vec<String> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        left.sort();
        assert_eq!(
            left,
            [
                "head-to-head.json",
                "match-2026-08-27-0001.json",
                "match-2026-10-31-0001.json",
                "match-notes.txt"
            ]
        );
        // The day after, the 66 day file is past 67 and goes too.
        let next = store.shred(now + 2 * DAY).unwrap();
        assert_eq!(
            next,
            Shredding {
                shredded: 1,
                kept: 1
            }
        );
        assert!(next.line().contains("shredded 1 match tally"));
        assert!(Shredding {
            shredded: 0,
            kept: 1
        }
        .line()
        .contains("Nothing to shred"));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn the_shredder_runs_at_start_and_then_daily_on_a_fake_clock() {
        let start = UNIX_EPOCH + 20_758 * DAY;
        let mut clock = ShredClock::default();
        assert!(clock.due(start), "a fresh server shreds at start");
        clock.ran(start);
        assert!(!clock.due(start + Duration::from_secs(60)));
        assert!(!clock.due(start + DAY - Duration::from_secs(1)));
        assert!(clock.due(start + DAY));
        clock.ran(start + DAY);
        assert!(clock.due(start), "a clock stepped back shreds at once");
    }
}
