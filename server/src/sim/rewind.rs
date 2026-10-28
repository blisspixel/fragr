//! Bounded hitscan lag compensation (#434 stage 5).
//!
//! A human client draws other fighters on a timeline that trails the server:
//! the snapshot's trip, the two-tick interpolation buffer, the Action's trip
//! and the wait for the next tick. It reports the fractional server tick it
//! was drawing (`Action::view_tick`). The server checks that claim against
//! what it has actually produced, turns it into a view lag measured from the
//! tick the Action arrived before, and clamps that lag to
//! [`MAX_REWIND_TICKS`]. A hitscan ray from that shooter then meets the
//! ordinary fighters where they stood at the shooter's view time, read from
//! a short history of hit volumes. Nothing else rewinds: world solids,
//! vehicles, civilians, campaign actors, projectiles, explosions and damage
//! all stay in the present, and damage is applied once by the ordinary path.
//!
//! Fairness bound: a victim can be struck at most 200 ms after the server
//! moved them, and only through cover that exists now. A body whose history
//! breaks inside the window (death, respawn, a teleport, a new movement
//! epoch, a step longer than [`MAX_STEP`]) is tested where it stands now.

use std::collections::VecDeque;
use uuid::Uuid;

/// The longest rewind: 4 ticks, 200 ms at 20 Hz. It covers the two-tick
/// interpolation buffer, the tick wait and about 50 ms of round trip in
/// full; beyond that a shooter leads the target by the excess.
pub const MAX_REWIND_TICKS: u64 = 4;
/// Ticks of hit volumes kept: 250 ms. One more than the longest rewind, so
/// an interpolated view at the bound always has both neighbours.
pub const HISTORY_TICKS: usize = 5;
/// Movement longer than this between two consecutive recorded ticks is a
/// discontinuity, never a path to interpolate along. It matches the client's
/// `RemotePresentation.SNAP_DISTANCE`.
pub const MAX_STEP: f32 = 3.0;

/// One fighter's hit volume at the end of a tick: feet, stance and the
/// movement epoch that changes on every respawn and placement.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Volume {
    pub id: Uuid,
    pub feet: [f32; 3],
    pub ducking: bool,
    pub epoch: u64,
}

#[derive(Debug, Default)]
struct Frame {
    tick: u64,
    bodies: Vec<Volume>,
}

/// Counters for the rewind path, kept for the life of the process and
/// published on `GET /status` as `ops.rewind`. One type, so the status block
/// cannot drift from what the simulation counts.
pub type RewindStats = crate::protocol::RewindTotals;

/// Why a reported view was refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ViewRefusal {
    NotFinite,
    Negative,
    /// A tick the server has not produced yet, so no client drew it.
    Future,
}

/// Turn a reported view tick into a view lag in ticks, measured from the tick
/// that will consume the Action (`received_at + 1`). `received_at` is the
/// newest tick the server has produced, and so the newest any client can
/// have drawn.
pub(crate) fn admit_view(view_tick: f64, received_at: u64) -> Result<f64, ViewRefusal> {
    if !view_tick.is_finite() {
        return Err(ViewRefusal::NotFinite);
    }
    if view_tick < 0.0 {
        return Err(ViewRefusal::Negative);
    }
    let newest = received_at as f64;
    if view_tick > newest {
        return Err(ViewRefusal::Future);
    }
    Ok(newest + 1.0 - view_tick)
}

/// A short ring of recorded hit volumes, reusing its frames' storage.
#[derive(Debug, Default)]
pub(crate) struct HitHistory {
    frames: VecDeque<Frame>,
}

impl HitHistory {
    pub fn clear(&mut self) {
        self.frames.clear();
    }

    /// Record the volumes at the end of `tick`. Older frames fall off.
    pub fn record(&mut self, tick: u64, bodies: impl Iterator<Item = Volume>) {
        let mut frame = if self.frames.len() >= HISTORY_TICKS {
            self.frames.pop_front().unwrap_or_default()
        } else {
            Frame::default()
        };
        frame.tick = tick;
        frame.bodies.clear();
        frame.bodies.extend(bodies);
        self.frames.push_back(frame);
    }

    fn body(&self, tick: u64, id: Uuid) -> Option<Volume> {
        let newest = self.frames.back()?.tick;
        let back = usize::try_from(newest.checked_sub(tick)?).ok()?;
        let frame = self.frames.get(self.frames.len().checked_sub(back + 1)?)?;
        (frame.tick == tick)
            .then(|| frame.bodies.iter().find(|body| body.id == id).copied())
            .flatten()
    }

    /// The volume `present` (the body now, during tick `now`) had at the
    /// fractional tick `view`, or None when its history does not reach that
    /// far unbroken. `view` must lie in `[now - MAX_REWIND_TICKS, now)`.
    pub fn volume_at(&self, present: Volume, now: u64, view: f64) -> Option<([f32; 3], bool)> {
        if !(view < now as f64 && view >= now.saturating_sub(MAX_REWIND_TICKS) as f64) {
            return None;
        }
        let from = view.floor() as u64;
        let weight = (view - from as f64) as f32;
        // Every recorded tick from the view to now, then the present body.
        let mut path = Vec::with_capacity(HISTORY_TICKS + 1);
        for tick in from..now {
            path.push(self.body(tick, present.id)?);
        }
        path.push(present);
        let unbroken = path.windows(2).all(|pair| {
            let [a, b] = [pair[0], pair[1]];
            let step = (0..3)
                .map(|i| (b.feet[i] - a.feet[i]).powi(2))
                .sum::<f32>()
                .sqrt();
            a.epoch == b.epoch && step <= MAX_STEP
        });
        if !unbroken {
            return None;
        }
        let (a, b) = (path[0], path[1]);
        let feet = std::array::from_fn(|i| a.feet[i] + (b.feet[i] - a.feet[i]) * weight);
        Some((feet, if weight < 0.5 { a.ducking } else { b.ducking }))
    }

    /// Recorded bodies across every frame, for the memory measurement.
    #[cfg(test)]
    pub fn stored_bodies(&self) -> usize {
        self.frames.iter().map(|f| f.bodies.len()).sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn volume(x: f32, epoch: u64) -> Volume {
        Volume {
            id: Uuid::from_u128(7),
            feet: [x, 0.0, 0.0],
            ducking: false,
            epoch,
        }
    }

    #[test]
    fn views_are_admitted_only_up_to_the_newest_tick() {
        assert_eq!(admit_view(100.0, 100), Ok(1.0));
        assert_eq!(admit_view(97.5, 100), Ok(3.5));
        assert_eq!(admit_view(100.25, 100), Err(ViewRefusal::Future));
        assert_eq!(admit_view(f64::NAN, 100), Err(ViewRefusal::NotFinite));
        assert_eq!(admit_view(f64::INFINITY, 100), Err(ViewRefusal::NotFinite));
        assert_eq!(admit_view(-1.0, 100), Err(ViewRefusal::Negative));
        // Far in the past is admitted; the shot clamps it to the bound.
        assert_eq!(admit_view(0.0, 100), Ok(101.0));
    }

    #[test]
    fn the_history_interpolates_and_keeps_only_its_window() {
        let mut history = HitHistory::default();
        for tick in 1..=8 {
            history.record(tick, std::iter::once(volume(tick as f32, 1)));
        }
        assert_eq!(history.stored_bodies(), HISTORY_TICKS);
        let present = volume(9.0, 1);
        let (feet, _) = history.volume_at(present, 9, 6.25).unwrap();
        assert!((feet[0] - 6.25).abs() < 1e-5, "{feet:?}");
        // Between the newest frame and the present body.
        let (feet, _) = history.volume_at(present, 9, 8.5).unwrap();
        assert!((feet[0] - 8.5).abs() < 1e-5, "{feet:?}");
        // Beyond the bound, in the present tick, or before the history.
        assert!(history.volume_at(present, 9, 4.5).is_none());
        assert!(history.volume_at(present, 9, 9.0).is_none());
        assert!(history.volume_at(present, 20, 16.5).is_none());
    }

    fn crowd(tick: u64, bodies: u128) -> impl Iterator<Item = Volume> {
        (0..bodies).map(move |i| Volume {
            id: Uuid::from_u128(i + 1),
            feet: [i as f32 + tick as f32 * 0.35, 0.0, 0.0],
            ducking: false,
            epoch: 1,
        })
    }

    #[test]
    fn the_history_at_the_64_connection_cap_is_about_13_kib() {
        let mut history = HitHistory::default();
        for tick in 1..=20 {
            history.record(tick, crowd(tick, 64));
        }
        assert_eq!(history.stored_bodies(), 64 * HISTORY_TICKS);
        assert_eq!(std::mem::size_of::<Volume>(), 40);
        // 64 fighters, five ticks, 40 bytes each: 12,800 bytes of volumes,
        // reused in place every tick.
        let bytes = history.stored_bodies() * std::mem::size_of::<Volume>();
        assert_eq!(bytes, 12_800);
    }

    /// Release timing of the history at 64 fighters; run with
    /// `cargo test -p fragr-server --release --lib rewind_cost -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn rewind_cost_at_64_fighters() {
        let mut history = HitHistory::default();
        let ticks = 200_000u64;
        let started = std::time::Instant::now();
        for tick in 1..=ticks {
            history.record(tick, crowd(tick, 64));
        }
        let record_ns = started.elapsed().as_nanos() as f64 / ticks as f64;
        let now = ticks + 1;
        let lookups = 200_000u64;
        let started = std::time::Instant::now();
        let mut found = 0u64;
        for i in 0..lookups {
            let id = Uuid::from_u128(u128::from(i % 64) + 1);
            let present = Volume {
                id,
                feet: [(i % 64) as f32 + now as f32 * 0.35, 0.0, 0.0],
                ducking: false,
                epoch: 1,
            };
            let view = now as f64 - 1.0 - (i % 300) as f64 / 100.0;
            found += u64::from(history.volume_at(present, now, view).is_some());
        }
        let lookup_ns = started.elapsed().as_nanos() as f64 / lookups as f64;
        assert_eq!(found, lookups);
        println!(
            "record 64 bodies: {record_ns:.0} ns per tick; one body lookup: {lookup_ns:.0} ns; one shot at 63 targets: {:.1} us",
            lookup_ns * 63.0 / 1000.0
        );
    }

    #[test]
    fn a_broken_history_is_never_interpolated() {
        let mut history = HitHistory::default();
        for tick in 1..=4 {
            history.record(tick, std::iter::once(volume(tick as f32, 1)));
        }
        // A new epoch now: the victim respawned since the view.
        assert!(history.volume_at(volume(5.0, 2), 5, 2.5).is_none());
        // A step longer than the snap distance: a teleport.
        assert!(history.volume_at(volume(9.0, 1), 5, 2.5).is_none());
        // Absent from a recorded frame: dead or seated then.
        let mut gap = HitHistory::default();
        gap.record(1, std::iter::once(volume(1.0, 1)));
        gap.record(2, std::iter::empty());
        gap.record(3, std::iter::once(volume(3.0, 1)));
        assert!(gap.volume_at(volume(4.0, 1), 4, 1.5).is_none());
        assert!(gap.volume_at(volume(4.0, 1), 4, 3.0).is_some());
    }
}
