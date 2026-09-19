//! Durable paid-request state. A receipt is written before its external effect.

use std::collections::BTreeMap;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::Path;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{validate_frame_id, validate_status_url, Error, Frame, HARD_CAP_USD};

const VERSION: u32 = 1;
const MAX_LEDGER_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Identity {
    pub model: String,
    pub request: Value,
}

impl Identity {
    pub fn new(model: &str, frame: &Frame) -> Self {
        Self {
            model: model.to_owned(),
            request: frame.body(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Stage {
    Reserved,
    Submitted {
        status_url: String,
    },
    Completed {
        status_url: String,
        urls: Vec<String>,
    },
    Downloaded {
        files: Vec<String>,
    },
    Stopped {
        status: String,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Job {
    /// None only for historical completed rows which did not record a request.
    pub identity: Option<Identity>,
    pub estimated_usd: f64,
    pub stage: Stage,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Event {
    Reserved {
        identity: Identity,
        estimated_usd: f64,
    },
    Submitted {
        status_url: String,
    },
    Completed {
        urls: Vec<String>,
    },
    Downloaded {
        files: Vec<String>,
    },
    Stopped {
        status: String,
    },
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Record {
    version: u32,
    id: String,
    event: Event,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Legacy {
    id: String,
    usd: f64,
    files: Vec<String>,
}

pub struct Ledger {
    // Closing this handle releases the lock, including after a process crash.
    file: File,
    jobs: BTreeMap<String, Job>,
}

impl Ledger {
    pub fn open(out_dir: &Path) -> Result<Self, Error> {
        std::fs::create_dir_all(out_dir).map_err(io_error)?;
        let mut file = OpenOptions::new()
            .create(true)
            .read(true)
            .append(true)
            .open(out_dir.join("ledger.jsonl"))
            .map_err(io_error)?;
        file.try_lock()
            .map_err(|e| Error::Io(format!("cannot lock asset ledger: {e}")))?;
        if file.metadata().map_err(io_error)?.len() > MAX_LEDGER_BYTES {
            return Err(Error::Io(
                "asset ledger exceeds 64 MiB; archive a completed batch".into(),
            ));
        }
        let mut text = String::new();
        (&mut file)
            .take(MAX_LEDGER_BYTES + 1)
            .read_to_string(&mut text)
            .map_err(io_error)?;
        if text.len() as u64 > MAX_LEDGER_BYTES {
            return Err(Error::Io("asset ledger grew beyond its size limit".into()));
        }
        let jobs = parse(&text)?;
        Ok(Self { file, jobs })
    }

    pub fn job(&self, id: &str) -> Option<&Job> {
        self.jobs.get(id)
    }

    pub fn record(&mut self, id: &str, event: Event) -> Result<(), Error> {
        validate_distinct_id(&self.jobs, id)?;
        let next = transition(id, self.jobs.get(id), &event)?;
        let record = Record {
            version: VERSION,
            id: id.to_owned(),
            event,
        };
        let line = serde_json::to_string(&record).map_err(|e| Error::Io(e.to_string()))?;
        if self.file.metadata().map_err(io_error)?.len() + line.len() as u64 + 1 > MAX_LEDGER_BYTES
        {
            return Err(Error::Io("asset ledger would exceed 64 MiB".into()));
        }
        writeln!(self.file, "{line}").map_err(io_error)?;
        self.file.sync_all().map_err(io_error)?;
        self.jobs.insert(id.to_owned(), next);
        Ok(())
    }

    /// Attach a dashboard-verified request to an uncertain reservation, locally.
    pub fn recover(&mut self, id: &str, request_id: &str) -> Result<(), Error> {
        if request_id.is_empty()
            || request_id.len() > 128
            || !request_id
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
        {
            return Err(Error::Spec(
                "request ID must contain only letters, numbers, - or _".into(),
            ));
        }
        self.record(
            id,
            Event::Submitted {
                status_url: format!("{}/requests/{request_id}/status", crate::API_BASE),
            },
        )
    }
}

fn parse(text: &str) -> Result<BTreeMap<String, Job>, Error> {
    if !text.is_empty() && !text.ends_with('\n') {
        return Err(Error::Io(
            "asset ledger has an unfinished line; reconcile it before retrying".into(),
        ));
    }
    let mut jobs: BTreeMap<String, Job> = BTreeMap::new();
    for (index, line) in text.lines().enumerate() {
        let value: Value = serde_json::from_str(line)
            .map_err(|_| Error::Io(format!("invalid asset ledger record on line {}", index + 1)))?;
        if value.get("version").is_some() {
            let record: Record = serde_json::from_value(value)
                .map_err(|e| Error::Io(format!("invalid asset ledger event: {e}")))?;
            if record.version != VERSION {
                return Err(Error::Io(format!(
                    "unsupported asset ledger version {}",
                    record.version
                )));
            }
            validate_distinct_id(&jobs, &record.id)?;
            let next = transition(&record.id, jobs.get(&record.id), &record.event)?;
            jobs.insert(record.id, next);
        } else {
            let legacy: Legacy = serde_json::from_value(value)
                .map_err(|e| Error::Io(format!("invalid legacy asset ledger row: {e}")))?;
            validate_frame_id(&legacy.id)?;
            validate_distinct_id(&jobs, &legacy.id)?;
            validate_cost(legacy.usd)?;
            validate_files(&legacy.files)?;
            if jobs.contains_key(&legacy.id) {
                return Err(Error::Io(format!(
                    "duplicate asset ledger ID {}",
                    legacy.id
                )));
            }
            jobs.insert(
                legacy.id,
                Job {
                    identity: None,
                    estimated_usd: legacy.usd,
                    stage: Stage::Downloaded {
                        files: legacy.files,
                    },
                },
            );
        }
    }
    Ok(jobs)
}

fn transition(id: &str, previous: Option<&Job>, event: &Event) -> Result<Job, Error> {
    validate_frame_id(id)?;
    if let Event::Reserved {
        identity,
        estimated_usd,
    } = event
    {
        if previous.is_some() {
            return Err(Error::Io(format!("asset {id} already has a reservation")));
        }
        validate_cost(*estimated_usd)?;
        crate::validation::validate_model_path(&identity.model)?;
        if !identity.request.is_object() {
            return Err(Error::Io(
                "asset reservation lacks a model or request object".into(),
            ));
        }
        return Ok(Job {
            identity: Some(identity.clone()),
            estimated_usd: *estimated_usd,
            stage: Stage::Reserved,
        });
    }
    let mut next = previous
        .cloned()
        .ok_or_else(|| Error::Io(format!("asset {id} has no reservation")))?;
    next.stage = match (&next.stage, event) {
        (Stage::Reserved, Event::Submitted { status_url }) => {
            validate_status_url(status_url)?;
            Stage::Submitted {
                status_url: status_url.clone(),
            }
        }
        (
            Stage::Submitted { status_url } | Stage::Completed { status_url, .. },
            Event::Completed { urls },
        ) => {
            if urls.len() > 64 {
                return Err(Error::Io("asset receipt exceeds 64 image URLs".into()));
            }
            for url in urls {
                crate::validate_download_url(url)?;
            }
            Stage::Completed {
                status_url: status_url.clone(),
                urls: urls.clone(),
            }
        }
        (Stage::Completed { urls, .. }, Event::Downloaded { files }) => {
            validate_files(files)?;
            if files.len() != urls.len() {
                return Err(Error::Io(
                    "download receipt does not match the completed image count".into(),
                ));
            }
            Stage::Downloaded {
                files: files.clone(),
            }
        }
        (Stage::Submitted { .. }, Event::Stopped { status })
            if matches!(status.as_str(), "failed" | "nsfw" | "canceled") =>
        {
            Stage::Stopped {
                status: status.clone(),
            }
        }
        _ => {
            return Err(Error::Io(format!(
                "invalid asset ledger transition for {id}"
            )))
        }
    };
    Ok(next)
}

fn validate_distinct_id(jobs: &BTreeMap<String, Job>, id: &str) -> Result<(), Error> {
    if jobs
        .keys()
        .any(|key| key != id && key.eq_ignore_ascii_case(id))
    {
        return Err(Error::Io("asset IDs differ only by filename case".into()));
    }
    Ok(())
}

fn validate_cost(usd: f64) -> Result<(), Error> {
    if !usd.is_finite() || !(0.0..=HARD_CAP_USD).contains(&usd) {
        return Err(Error::Io(
            "asset receipt has an invalid estimated cost".into(),
        ));
    }
    Ok(())
}

fn validate_files(files: &[String]) -> Result<(), Error> {
    if files.is_empty() {
        return Err(Error::Io("download receipt has no files".into()));
    }
    let mut unique = std::collections::BTreeSet::new();
    for file in files {
        crate::validation::validate_file_name(file)?;
        if !unique.insert(file.to_ascii_lowercase()) {
            return Err(Error::Io("download receipt repeats a file".into()));
        }
    }
    Ok(())
}

fn io_error(error: std::io::Error) -> Error {
    Error::Io(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TestDir;
    use serde_json::json;

    fn reservation() -> Event {
        Event::Reserved {
            identity: Identity {
                model: "model/image".into(),
                request: json!({"prompt":"p"}),
            },
            estimated_usd: 0.02,
        }
    }

    #[test]
    fn receipts_survive_reopen_and_lock_excludes_another_writer() {
        let dir = TestDir::new();
        let mut ledger = Ledger::open(&dir.0).unwrap();
        ledger.record("tack", reservation()).unwrap();
        assert!(ledger.record("TACK", reservation()).is_err());
        assert!(Ledger::open(&dir.0).is_err());
        drop(ledger);
        let mut ledger = Ledger::open(&dir.0).unwrap();
        assert_eq!(ledger.job("tack").unwrap().stage, Stage::Reserved);
        ledger.recover("tack", "request-1").unwrap();
        ledger
            .record(
                "tack",
                Event::Completed {
                    urls: vec!["https://cdn.example/a.png".into()],
                },
            )
            .unwrap();
        ledger
            .record(
                "tack",
                Event::Downloaded {
                    files: vec!["tack_0.png".into()],
                },
            )
            .unwrap();
        let expected = ledger.job("tack").unwrap().clone();
        drop(ledger);
        let ledger = Ledger::open(&dir.0).unwrap();
        assert_eq!(ledger.job("tack"), Some(&expected));
        assert_eq!(expected.estimated_usd, 0.02);
    }

    #[test]
    fn corrupt_or_contradictory_history_never_becomes_an_empty_ledger() {
        let valid = "{\"id\":\"tack\",\"usd\":0.02,\"files\":[\"tack_0.png\"]}\n";
        for bad in [
            valid.trim_end().to_owned(),
            format!("{valid}not json\n"),
            format!("{valid}{valid}"),
            format!("{valid}{}", valid.replace("tack", "TACK")),
            format!("{valid}\n"),
            "{\"version\":2,\"id\":\"tack\",\"event\":{\"type\":\"completed\",\"urls\":[]}}\n"
                .into(),
            "{\"version\":1,\"id\":\"tack\",\"event\":{\"type\":\"completed\",\"urls\":[]}}\n"
                .into(),
            "{\"id\":\"tack\",\"usd\":0.02,\"files\":[\"../escape.png\"]}\n".into(),
            "{\"id\":\"tack\",\"usd\":0.02,\"files\":[],\"extra\":true}\n".into(),
        ] {
            let dir = TestDir::new();
            std::fs::write(dir.0.join("ledger.jsonl"), &bad).unwrap();
            assert!(Ledger::open(&dir.0).is_err(), "{bad}");
            assert_eq!(
                std::fs::read_to_string(dir.0.join("ledger.jsonl")).unwrap(),
                bad
            );
        }
        let jobs = parse(valid).unwrap();
        assert!(jobs["tack"].identity.is_none());
        assert_eq!(
            jobs["tack"].stage,
            Stage::Downloaded {
                files: vec!["tack_0.png".into()]
            }
        );
    }

    #[test]
    fn invalid_transitions_leave_the_receipt_unchanged() {
        let dir = TestDir::new();
        let mut ledger = Ledger::open(&dir.0).unwrap();
        assert!(ledger.recover("tack", "unknown").is_err());
        ledger.record("tack", reservation()).unwrap();
        for id in ["", "../x", "x?y", "x/y", &"a".repeat(129)] {
            assert!(ledger.recover("tack", id).is_err());
        }
        assert!(ledger.record("tack", reservation()).is_err());
        assert!(ledger
            .record(
                "tack",
                Event::Submitted {
                    status_url: "https://evil.example/requests/1/status".into()
                }
            )
            .is_err());
        ledger.recover("tack", "r1").unwrap();
        assert!(ledger.recover("tack", "r2").is_err());
        assert!(ledger
            .record(
                "tack",
                Event::Stopped {
                    status: "processing".into()
                }
            )
            .is_err());
        ledger
            .record("tack", Event::Completed { urls: vec![] })
            .unwrap();
        assert!(ledger
            .record("tack", Event::Downloaded { files: vec![] })
            .is_err());
        assert!(ledger
            .record(
                "tack",
                Event::Completed {
                    urls: vec!["http://cdn.example/x".into()]
                }
            )
            .is_err());
        assert!(ledger
            .record(
                "tack",
                Event::Completed {
                    urls: vec!["https://cdn.example/x".into(); 65]
                }
            )
            .is_err());
        ledger
            .record(
                "tack",
                Event::Completed {
                    urls: vec!["https://cdn.example/x".into()],
                },
            )
            .unwrap();
        for files in [
            vec!["x.png".into(), "x.png".into()],
            vec!["x.png".into(), "y.png".into()],
        ] {
            assert!(ledger.record("tack", Event::Downloaded { files }).is_err());
        }
        ledger
            .record(
                "tack",
                Event::Downloaded {
                    files: vec!["tack_0.png".into()],
                },
            )
            .unwrap();
        assert!(ledger.record("tack", reservation()).is_err());
        drop(ledger);
        assert!(matches!(
            Ledger::open(&dir.0).unwrap().job("tack").unwrap().stage,
            Stage::Downloaded { .. }
        ));
    }

    #[test]
    fn invalid_costs_and_requests_fail_before_a_record_is_written() {
        let dir = TestDir::new();
        let mut ledger = Ledger::open(&dir.0).unwrap();
        for cost in [f64::NAN, f64::INFINITY, -0.1, 5.01] {
            let Event::Reserved { identity, .. } = reservation() else {
                unreachable!()
            };
            assert!(ledger
                .record(
                    "tack",
                    Event::Reserved {
                        identity,
                        estimated_usd: cost
                    }
                )
                .is_err());
        }
        for identity in [
            Identity {
                model: "../image".into(),
                request: json!({}),
            },
            Identity {
                model: "model".into(),
                request: json!(null),
            },
        ] {
            assert!(ledger
                .record(
                    "tack",
                    Event::Reserved {
                        identity,
                        estimated_usd: 0.02
                    }
                )
                .is_err());
        }
        assert_eq!(
            std::fs::metadata(dir.0.join("ledger.jsonl")).unwrap().len(),
            0
        );
    }

    #[test]
    fn unreadable_or_oversized_ledger_is_not_treated_as_missing() {
        let dir = TestDir::new();
        std::fs::create_dir(dir.0.join("ledger.jsonl")).unwrap();
        assert!(Ledger::open(&dir.0).is_err());
        std::fs::remove_dir(dir.0.join("ledger.jsonl")).unwrap();
        let file = File::create(dir.0.join("ledger.jsonl")).unwrap();
        file.set_len(MAX_LEDGER_BYTES + 1).unwrap();
        drop(file);
        assert!(Ledger::open(&dir.0).is_err());
    }
}
