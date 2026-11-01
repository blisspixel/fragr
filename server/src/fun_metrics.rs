//! Fun metrics: a host's own tally of how matches play, off unless the host
//! switches it on (`--fun-metrics`, or the desktop host's switch), and the
//! one place the bot survey and the server agree on what a frag a minute,
//! a lead change or a time to contact means.
//!
//! The policy of record is `docs/PRIVACY.md`. This module is the code that
//! enforces it:
//!
//! - [`record`] holds the only shape that reaches the disk. It is built from
//!   counts, durations, booleans and closed enums, so it cannot hold an
//!   address, a callsign, an id, a ticket, chat or a hardware fact; a test
//!   reads the field list against the policy and fails on anything new.
//! - [`observe`] reads the authoritative session tick by tick and folds it
//!   into one match's tally. Fighter ids live only in its working memory and
//!   are dropped with it.
//! - [`store`] writes one file per match under the host's run directory and
//!   shreds files older than [`RETENTION_DAYS`] at start and once a day.
//!
//! Nothing here opens a socket. The Union would keep it forever. We do not.

pub mod host;
pub mod observe;
#[cfg(test)]
mod observe_tests;
#[cfg(test)]
mod privacy_tests;
pub mod record;
pub mod sight;
pub mod store;
mod table;
#[cfg(test)]
mod wire_tests;

pub use host::HostRecorder;
pub use observe::Observer;
pub use record::{FunRecord, MatchTally, Samples, TickHealth, WeaponTable, ZoneTally};
pub use store::{FunStore, ShredClock, Shredding};

/// Days a record lives before it is shredded.
pub const RETENTION_DAYS: u64 = 67;

/// A death this soon after the fighter's spawn counts against the spawn:
/// three seconds at 20 Hz.
pub const SPAWN_DEATH_TICKS: u64 = 60;
/// A frag this close to a power pad, this soon after it returned, contests it.
pub const CONTEST_RADIUS: f32 = 8.0;
pub const CONTEST_TICKS: u64 = 100;
/// A claim this soon after a pad returned kept an appointment with its clock.
pub const APPOINTMENT_TICKS: u64 = 20;
/// The simulation's rate, for turning ticks into seconds.
pub const TICKS_PER_SECOND: f64 = 20.0;

/// Median and quartiles of a list.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct Spread {
    pub count: u64,
    pub median: f64,
    pub p25: f64,
    pub p75: f64,
}

/// The one quantile reading every survey and summary uses: nearest rank on
/// the sorted list.
pub fn spread(values: &[f64]) -> Spread {
    if values.is_empty() {
        return Spread::default();
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(f64::total_cmp);
    let at = |share: f64| {
        let index = ((sorted.len() - 1) as f64 * share).round() as usize;
        sorted[index]
    };
    Spread {
        count: sorted.len() as u64,
        median: at(0.5),
        p25: at(0.25),
        p75: at(0.75),
    }
}

/// `part` of `whole`, zero when there is no whole.
pub fn share(part: u64, whole: u64) -> f64 {
    if whole == 0 {
        0.0
    } else {
        part as f64 / whole as f64
    }
}

/// `count` per live minute.
pub fn per_minute(count: u64, live_ticks: u64) -> f64 {
    let minutes = live_ticks as f64 / TICKS_PER_SECOND / 60.0;
    if minutes > 0.0 {
        count as f64 / minutes
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spread_reads_median_and_quartiles() {
        let s = spread(&[5.0, 1.0, 3.0, 2.0, 4.0]);
        assert_eq!((s.count, s.median, s.p25, s.p75), (5, 3.0, 2.0, 4.0));
        assert_eq!(spread(&[]), Spread::default());
    }

    #[test]
    fn rates_read_zero_without_a_whole() {
        assert_eq!(share(3, 0), 0.0);
        assert_eq!(share(1, 4), 0.25);
        assert_eq!(per_minute(10, 0), 0.0);
        assert_eq!(per_minute(10, 20 * 60), 10.0);
    }
}
