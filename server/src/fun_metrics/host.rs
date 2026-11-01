//! The run loop's side of fun metrics: one observer per match, the tick
//! timings beside it, a file when the match ends and the shredder on its
//! daily clock.
use super::store::{FunStore, ShredClock};
use super::{Observer, TickHealth};
use crate::protocol::ServerMessage;
use crate::session::GameSession;
use std::time::{Duration, SystemTime};

pub struct HostRecorder {
    store: FunStore,
    observer: Option<Observer>,
    ticks: crate::bench::TickStats,
    clock: ShredClock,
    warned: bool,
    filed: u32,
}

fn micros(ms: f64) -> u32 {
    (ms * 1000.0).round().clamp(0.0, f64::from(u32::MAX)) as u32
}

impl HostRecorder {
    /// Announce the tally in the log and shred what is past its days.
    pub fn start(store: FunStore, now: SystemTime) -> Self {
        tracing::info!(
            target: crate::logging::STARTUP_TARGET,
            "Fun metrics on: match tallies only, no callsigns, ids or addresses, kept in {} for {} days and then shredded.",
            store.dir().display(),
            super::RETENTION_DAYS
        );
        let mut recorder = Self {
            store,
            observer: None,
            ticks: crate::bench::TickStats::new(),
            clock: ShredClock::default(),
            warned: false,
            filed: 0,
        };
        recorder.shred_if_due(now);
        recorder
    }

    /// Matches filed since the server started.
    pub fn filed(&self) -> u32 {
        self.filed
    }

    pub fn dir(&self) -> &std::path::Path {
        self.store.dir()
    }

    /// One tick's state and broadcasts.
    pub fn observe(&mut self, session: &GameSession, messages: &[ServerMessage]) {
        self.observer
            .get_or_insert_with(|| Observer::new(session))
            .observe(session, messages);
    }

    /// How long the tick's work took, for the record's tick health.
    pub fn tick_took(&mut self, elapsed: Duration) {
        if self.observer.is_some() {
            self.ticks.record_tick(elapsed, 0);
        }
    }

    /// File a match that ended, and shred when the day comes round.
    pub fn after_tick(&mut self, now: SystemTime) {
        if self.observer.as_ref().is_some_and(Observer::finished) {
            self.file(now);
        }
        self.shred_if_due(now);
    }

    /// At shutdown: file the match in progress if any of it was played.
    pub fn finish(&mut self, now: SystemTime) {
        if self.observer.as_ref().is_some_and(Observer::played) {
            self.file(now);
        }
    }

    fn tick_health(&self) -> Option<TickHealth> {
        if self.ticks.ticks() == 0 {
            return None;
        }
        let report = self.ticks.report(0, 0);
        Some(TickHealth {
            ticks: report.ticks,
            p50_us: micros(report.tick_ms.p50),
            p99_us: micros(report.tick_ms.p99),
            max_us: micros(report.tick_ms.max),
            over_budget: report.ticks_over_budget,
        })
    }

    fn file(&mut self, now: SystemTime) {
        let health = self.tick_health();
        self.ticks = crate::bench::TickStats::new();
        let Some(observer) = self.observer.take() else {
            return;
        };
        if !observer.played() {
            return;
        }
        let record = observer.into_record(health);
        match self.store.write(&record, now) {
            Ok(path) => {
                self.filed += 1;
                tracing::info!(
                    "Fun metrics: filed {} (the match, not the people in it).",
                    path.file_name()
                        .and_then(|name| name.to_str())
                        .unwrap_or_default()
                );
            }
            Err(error) if !self.warned => {
                self.warned = true;
                tracing::warn!(
                    "Fun metrics could not file a match in {}: {error}. The match goes on; later failures stay quiet.",
                    self.store.dir().display()
                );
            }
            Err(_) => {}
        }
    }

    fn shred_if_due(&mut self, now: SystemTime) {
        if !self.clock.due(now) {
            return;
        }
        self.clock.ran(now);
        match self.store.shred(now) {
            Ok(pass) if pass.shredded > 0 => tracing::info!("{}", pass.line()),
            Ok(pass) => tracing::debug!("{}", pass.line()),
            Err(error) => tracing::warn!(
                "Fun metrics shredder could not read {}: {error}",
                self.store.dir().display()
            ),
        }
    }
}
