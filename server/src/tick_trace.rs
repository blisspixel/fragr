//! Opt-in per-tick timing for stutter diagnosis. Off unless the host passes
//! `--tick-trace <path>` or sets `FRAGR_TICK_TRACE` to an absolute path.
//!
//! Each line is one NDJSON record: a header, one record per served tick and a
//! completion footer on clean shutdown. A tick record carries the same tick
//! number as that tick's Snapshot, so a client trace joins it exactly without
//! clock agreement. Wall-clock microseconds are included for loose alignment
//! only; they agree with a client clock only on the same machine.
//!
//! The tick loop never writes the file. It offers each record to a bounded
//! queue and a writer thread does the I/O. A full queue drops the record and
//! counts it, so a slow disk cannot become the stall being measured.

use crate::protocol::BuildInfo;
use serde::{Deserialize, Serialize};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, SyncSender, TrySendError};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const TICK_TRACE_VERSION: u32 = 1;
/// Environment fallback for a host the player cannot pass flags to, such as
/// the desktop host or the local campaign process the client launches.
pub const TICK_TRACE_ENV: &str = "FRAGR_TICK_TRACE";
/// About fifty seconds of ticks. Only a writer stalled that long drops records.
const QUEUE_RECORDS: usize = 1024;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "record", rename_all = "snake_case", deny_unknown_fields)]
pub enum TickTraceRecord {
    Header {
        version: u32,
        /// Nominal tick period.
        tick_us: u64,
        build: BuildInfo,
        started_unix_us: u64,
    },
    Tick(TickSample),
    /// Written only on clean shutdown. Its absence means the trace was cut.
    Complete {
        ticks: u64,
        /// Records the queue refused. Their ticks are absent from the file.
        dropped: u64,
        over_budget: u64,
        skipped_periods: u64,
    },
}

/// One served tick. Durations are microseconds measured on the monotonic clock.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TickSample {
    /// The Snapshot tick this handler produced.
    pub tick: u64,
    /// Wall clock when the handler began, for same-machine alignment.
    pub unix_us: u64,
    /// How long after its scheduled deadline the handler began. Command
    /// handling between ticks and a busy runtime both show up here.
    pub late_us: u64,
    /// Whole tick periods the interval skipped before this tick. Nonzero
    /// means the server fell more than one period behind and did not catch up.
    pub skipped: u64,
    /// Session simulation, message building and local run persistence.
    pub sim_us: u64,
    /// Serializing this tick's messages once to count their bytes.
    pub measure_us: u64,
    /// Queuing broadcasts and unicasts to every client writer. Socket
    /// completion and peer receipt are not included.
    pub fanout_us: u64,
    /// The whole handler, from start to the end of delivery queuing.
    pub total_us: u64,
    pub clients: u32,
    pub messages: u32,
    pub bytes: u64,
    pub overflows: u64,
}

impl TickSample {
    pub fn over_budget(&self, budget: Duration) -> bool {
        u128::from(self.total_us) >= budget.as_micros()
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct TickTraceSummary {
    pub ticks: u64,
    pub dropped: u64,
    pub over_budget: u64,
    pub skipped_periods: u64,
}

/// Whole periods between two scheduled deadlines beyond the expected one.
/// Rounds to the nearest period so timer jitter never reads as a skip.
pub fn skipped_periods(previous: Option<Instant>, deadline: Instant, period: Duration) -> u64 {
    let Some(previous) = previous else {
        return 0;
    };
    let period_ns = period.as_nanos();
    if period_ns == 0 {
        return 0;
    }
    let gap = deadline.saturating_duration_since(previous).as_nanos();
    let periods = (gap + period_ns / 2) / period_ns;
    u64::try_from(periods.saturating_sub(1)).unwrap_or(u64::MAX)
}

pub fn micros(duration: Duration) -> u64 {
    u64::try_from(duration.as_micros()).unwrap_or(u64::MAX)
}

pub fn unix_micros(at: SystemTime) -> u64 {
    at.duration_since(UNIX_EPOCH).map(micros).unwrap_or(0)
}

/// The environment path, when set. It must be absolute: a launched host's
/// working directory is the client's, which a player cannot see.
pub fn path_from_env() -> io::Result<Option<PathBuf>> {
    path_from_value(std::env::var_os(TICK_TRACE_ENV))
}

fn path_from_value(value: Option<std::ffi::OsString>) -> io::Result<Option<PathBuf>> {
    match value {
        None => Ok(None),
        Some(raw) if raw.is_empty() => Ok(None),
        Some(raw) => {
            let path = PathBuf::from(raw);
            if path.is_absolute() {
                Ok(Some(path))
            } else {
                Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("{TICK_TRACE_ENV} must be an absolute path"),
                ))
            }
        }
    }
}

pub struct TickTrace {
    tx: Option<SyncSender<TickTraceRecord>>,
    worker: Option<JoinHandle<io::Result<()>>>,
    budget: Duration,
    previous_deadline: Option<Instant>,
    summary: TickTraceSummary,
}

impl TickTrace {
    /// Create or truncate `path`. Failure to open is returned before the
    /// match starts, because the host asked for this evidence.
    pub fn create(path: &Path, budget: Duration, build: BuildInfo) -> io::Result<Self> {
        let file = std::fs::File::create(path)?;
        Self::to_writer(file, budget, build, SystemTime::now())
    }

    pub fn to_writer(
        writer: impl Write + Send + 'static,
        budget: Duration,
        build: BuildInfo,
        started: SystemTime,
    ) -> io::Result<Self> {
        Self::with_capacity(writer, budget, build, started, QUEUE_RECORDS)
    }

    fn with_capacity(
        writer: impl Write + Send + 'static,
        budget: Duration,
        build: BuildInfo,
        started: SystemTime,
        capacity: usize,
    ) -> io::Result<Self> {
        let (tx, rx) = mpsc::sync_channel(capacity.max(1));
        let header = TickTraceRecord::Header {
            version: TICK_TRACE_VERSION,
            tick_us: micros(budget),
            build,
            started_unix_us: unix_micros(started),
        };
        // The header goes first on an empty queue, so it cannot be refused.
        tx.try_send(header)
            .map_err(|_| io::Error::other("tick trace queue refused its header"))?;
        let worker = std::thread::Builder::new()
            .name("tick-trace".into())
            .spawn(move || write_records(writer, rx))?;
        Ok(TickTrace {
            tx: Some(tx),
            worker: Some(worker),
            budget,
            previous_deadline: None,
            summary: TickTraceSummary::default(),
        })
    }

    /// Note this tick's scheduled deadline and return the periods skipped
    /// since the previous one.
    pub fn deadline(&mut self, deadline: Instant) -> u64 {
        let skipped = skipped_periods(self.previous_deadline, deadline, self.budget);
        self.previous_deadline = Some(deadline);
        skipped
    }

    /// Offer one tick. Never blocks; a full or closed queue counts a drop.
    pub fn record(&mut self, sample: TickSample) {
        self.summary.ticks += 1;
        self.summary.skipped_periods = self.summary.skipped_periods.saturating_add(sample.skipped);
        if sample.over_budget(self.budget) {
            self.summary.over_budget += 1;
        }
        let Some(tx) = &self.tx else {
            self.summary.dropped += 1;
            return;
        };
        match tx.try_send(TickTraceRecord::Tick(sample)) {
            Ok(()) => {}
            Err(TrySendError::Full(_)) | Err(TrySendError::Disconnected(_)) => {
                self.summary.dropped += 1;
            }
        }
    }

    pub fn summary(&self) -> TickTraceSummary {
        self.summary
    }

    /// Write the footer, close the queue and wait for the writer. The footer
    /// is offered last; if the queue is full it blocks only this shutdown.
    pub fn finish(mut self) -> io::Result<TickTraceSummary> {
        self.close()
    }

    fn close(&mut self) -> io::Result<TickTraceSummary> {
        let summary = self.summary;
        if let Some(tx) = self.tx.take() {
            let _ = tx.send(TickTraceRecord::Complete {
                ticks: summary.ticks,
                dropped: summary.dropped,
                over_budget: summary.over_budget,
                skipped_periods: summary.skipped_periods,
            });
        }
        match self.worker.take() {
            Some(worker) => match worker.join() {
                Ok(result) => result.map(|()| summary),
                Err(_) => Err(io::Error::other("tick trace writer panicked")),
            },
            None => Ok(summary),
        }
    }
}

impl Drop for TickTrace {
    fn drop(&mut self) {
        if let Err(error) = self.close() {
            tracing::warn!("Tick trace did not finish cleanly: {error}");
        }
    }
}

/// Flush whenever the queue is momentarily empty, so a cut process loses at
/// most the records still in flight. After a write error the rest are drained
/// and discarded so the sender never sees backpressure from a dead file.
fn write_records(writer: impl Write, rx: Receiver<TickTraceRecord>) -> io::Result<()> {
    let mut out = BufWriter::new(writer);
    let mut failure: Option<io::Error> = None;
    while let Ok(first) = rx.recv() {
        let mut next = Some(first);
        while let Some(record) = next.take() {
            if failure.is_none() {
                if let Err(error) = write_line(&mut out, &record) {
                    tracing::warn!("Tick trace stopped writing: {error}");
                    failure = Some(error);
                }
            }
            next = rx.try_recv().ok();
        }
        if failure.is_none() {
            if let Err(error) = out.flush() {
                tracing::warn!("Tick trace stopped writing: {error}");
                failure = Some(error);
            }
        }
    }
    match failure {
        Some(error) => Err(error),
        None => out.flush(),
    }
}

fn write_line(out: &mut impl Write, record: &TickTraceRecord) -> io::Result<()> {
    serde_json::to_writer(&mut *out, record).map_err(io::Error::other)?;
    out.write_all(b"\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Clone, Default)]
    struct Shared(Arc<Mutex<Vec<u8>>>);

    impl Write for Shared {
        fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(buf);
            Ok(buf.len())
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    /// Accepts `limit` bytes, then fails every write.
    struct Failing {
        limit: usize,
        written: usize,
    }

    impl Write for Failing {
        fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
            if self.written + buf.len() > self.limit {
                return Err(io::Error::other("disk full"));
            }
            self.written += buf.len();
            Ok(buf.len())
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    /// Blocks inside its first write until released, so the queue fills.
    /// `entered` is set once the writer is parked there.
    struct Gate {
        release: Arc<(Mutex<bool>, std::sync::Condvar)>,
        entered: Arc<std::sync::atomic::AtomicBool>,
        sink: Shared,
    }

    impl Write for Gate {
        fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
            let (lock, wake) = &*self.release;
            let mut open = lock.lock().unwrap();
            self.entered
                .store(true, std::sync::atomic::Ordering::SeqCst);
            while !*open {
                open = wake.wait(open).unwrap();
            }
            self.sink.write(buf)
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    fn build() -> BuildInfo {
        BuildInfo {
            crate_version: "0.0.0".into(),
            release: None,
            commit: "unknown".into(),
        }
    }

    fn sample(tick: u64, total_us: u64, skipped: u64) -> TickSample {
        TickSample {
            tick,
            unix_us: 1_000 + tick,
            late_us: 7,
            skipped,
            sim_us: total_us / 2,
            measure_us: 1,
            fanout_us: 2,
            total_us,
            clients: 3,
            messages: 4,
            bytes: 500,
            overflows: 0,
        }
    }

    fn records(sink: &Shared) -> Vec<TickTraceRecord> {
        let bytes = sink.0.lock().unwrap().clone();
        String::from_utf8(bytes)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect()
    }

    #[test]
    fn writes_header_ticks_and_footer_in_order() {
        let sink = Shared::default();
        let mut trace = TickTrace::to_writer(
            sink.clone(),
            Duration::from_millis(50),
            build(),
            UNIX_EPOCH + Duration::from_micros(42),
        )
        .unwrap();
        trace.record(sample(10, 1_200, 0));
        trace.record(sample(11, 50_000, 2));
        let summary = trace.finish().unwrap();
        assert_eq!(
            summary,
            TickTraceSummary {
                ticks: 2,
                dropped: 0,
                over_budget: 1,
                skipped_periods: 2
            }
        );
        let lines = records(&sink);
        assert_eq!(lines.len(), 4);
        assert_eq!(
            lines[0],
            TickTraceRecord::Header {
                version: TICK_TRACE_VERSION,
                tick_us: 50_000,
                build: build(),
                started_unix_us: 42,
            }
        );
        assert_eq!(lines[1], TickTraceRecord::Tick(sample(10, 1_200, 0)));
        assert_eq!(lines[2], TickTraceRecord::Tick(sample(11, 50_000, 2)));
        assert_eq!(
            lines[3],
            TickTraceRecord::Complete {
                ticks: 2,
                dropped: 0,
                over_budget: 1,
                skipped_periods: 2
            }
        );
    }

    #[test]
    fn a_full_queue_drops_and_counts_instead_of_blocking_the_tick() {
        let sink = Shared::default();
        let release = Arc::new((Mutex::new(false), std::sync::Condvar::new()));
        let entered = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let gate = Gate {
            release: release.clone(),
            entered: entered.clone(),
            sink: sink.clone(),
        };
        let mut trace =
            TickTrace::with_capacity(gate, Duration::from_millis(50), build(), UNIX_EPOCH, 2)
                .unwrap();
        // Wait until the writer has taken the header and is parked in its
        // first flush, so the queue is empty and the count below is exact
        // however the threads are scheduled.
        let parked = Instant::now();
        while !entered.load(std::sync::atomic::Ordering::SeqCst) {
            assert!(
                parked.elapsed() < Duration::from_secs(30),
                "writer never reached its first write"
            );
            std::thread::yield_now();
        }
        // Two records fit the empty queue; every later one must be refused at
        // once rather than wait for the disk.
        let started = Instant::now();
        for tick in 0..50 {
            trace.record(sample(tick, 100, 0));
        }
        assert!(started.elapsed() < Duration::from_secs(1), "record blocked");
        let dropped = trace.summary().dropped;
        assert_eq!(dropped, 48);
        {
            let (lock, wake) = &*release;
            *lock.lock().unwrap() = true;
            wake.notify_all();
        }
        let summary = trace.finish().unwrap();
        assert_eq!(summary.ticks, 50);
        let lines = records(&sink);
        let ticks = lines
            .iter()
            .filter(|r| matches!(r, TickTraceRecord::Tick(_)))
            .count() as u64;
        assert_eq!(ticks + summary.dropped, 50);
        assert!(matches!(
            lines.last(),
            Some(TickTraceRecord::Complete { dropped, .. }) if *dropped == summary.dropped
        ));
    }

    #[test]
    fn a_write_failure_is_reported_and_never_blocks_later_records() {
        let mut trace = TickTrace::to_writer(
            Failing {
                limit: 0,
                written: 0,
            },
            Duration::from_millis(50),
            build(),
            UNIX_EPOCH,
        )
        .unwrap();
        for tick in 0..2_000 {
            trace.record(sample(tick, 100, 0));
        }
        let error = trace.finish().expect_err("a failed file must be reported");
        assert_eq!(error.to_string(), "disk full");
    }

    #[test]
    fn create_refuses_an_unwritable_path_before_the_match() {
        let missing = std::env::temp_dir()
            .join(format!("fragr-no-dir-{}", uuid::Uuid::new_v4()))
            .join("trace.ndjson");
        assert!(TickTrace::create(&missing, Duration::from_millis(50), build()).is_err());
    }

    #[test]
    fn create_writes_a_file_that_reads_back() {
        let path = std::env::temp_dir().join(format!("fragr-tick-{}.ndjson", uuid::Uuid::new_v4()));
        let mut trace = TickTrace::create(&path, Duration::from_millis(50), build()).unwrap();
        trace.record(sample(1, 10, 0));
        drop(trace); // Drop finishes the file too.
        let text = std::fs::read_to_string(&path).unwrap();
        let _ = std::fs::remove_file(&path);
        let parsed: Vec<TickTraceRecord> = text
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert_eq!(parsed.len(), 3);
        assert!(matches!(
            parsed[2],
            TickTraceRecord::Complete { ticks: 1, .. }
        ));
    }

    #[test]
    fn records_reject_unknown_fields() {
        let line = r#"{"record":"tick","tick":1,"unix_us":0,"late_us":0,"skipped":0,"sim_us":0,"measure_us":0,"fanout_us":0,"total_us":0,"clients":0,"messages":0,"bytes":0,"overflows":0,"extra":1}"#;
        assert!(serde_json::from_str::<TickTraceRecord>(line).is_err());
    }

    #[test]
    fn skipped_periods_counts_whole_missed_deadlines_only() {
        let period = Duration::from_millis(50);
        let start = Instant::now();
        assert_eq!(skipped_periods(None, start, period), 0);
        assert_eq!(skipped_periods(Some(start), start + period, period), 0);
        // Timer jitter around one period is not a skip.
        assert_eq!(
            skipped_periods(Some(start), start + Duration::from_millis(74), period),
            0
        );
        assert_eq!(
            skipped_periods(Some(start), start + Duration::from_millis(150), period),
            2
        );
        // A deadline that did not advance never underflows.
        assert_eq!(skipped_periods(Some(start + period), start, period), 0);
        assert_eq!(
            skipped_periods(Some(start), start + period, Duration::ZERO),
            0
        );
    }

    #[test]
    fn deadline_tracks_the_previous_schedule() {
        let mut trace = TickTrace::to_writer(
            Shared::default(),
            Duration::from_millis(50),
            build(),
            UNIX_EPOCH,
        )
        .unwrap();
        let start = Instant::now();
        assert_eq!(trace.deadline(start), 0);
        assert_eq!(trace.deadline(start + Duration::from_millis(50)), 0);
        assert_eq!(trace.deadline(start + Duration::from_millis(200)), 2);
    }

    #[test]
    fn environment_path_must_be_absolute_and_may_be_absent() {
        assert!(path_from_value(None).unwrap().is_none());
        assert!(path_from_value(Some("".into())).unwrap().is_none());
        let relative = path_from_value(Some("trace.ndjson".into())).unwrap_err();
        assert_eq!(relative.kind(), io::ErrorKind::InvalidInput);
        let absolute = std::env::temp_dir().join("trace.ndjson");
        assert_eq!(
            path_from_value(Some(absolute.clone().into_os_string())).unwrap(),
            Some(absolute)
        );
    }

    #[test]
    fn time_helpers_saturate() {
        assert_eq!(micros(Duration::from_millis(3)), 3_000);
        assert_eq!(micros(Duration::MAX), u64::MAX);
        assert_eq!(unix_micros(UNIX_EPOCH + Duration::from_micros(9)), 9);
        assert_eq!(unix_micros(UNIX_EPOCH - Duration::from_secs(1)), 0);
    }
}
