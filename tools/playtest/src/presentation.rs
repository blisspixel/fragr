//! The client's remote presentation clock, mirrored for the probes (#525).
//!
//! `client/scripts/remote_presentation.gd` draws other fighters on a timeline
//! that trails the newest snapshot by an adaptive buffer: one tick, a margin,
//! and the 90th percentile lateness of the last 32 arrivals against the
//! earliest, between 1.2 and 2 ticks, slewed at 2 ticks a second wider and
//! 0.5 narrower. This is the same arithmetic in microseconds and ticks, so
//! the rewind matrix and the peek probe draw where the client would.
//! `client/golden/presentation_vectors.json`, written by the ignored test
//! below and replayed by `client/scripts/test_remote_presentation.gd`, pins
//! both to the same numbers.

use serde::Serialize;
use std::collections::VecDeque;

pub const TICK_USEC: i64 = 50_000;
pub const BASE_TICKS: f64 = 1.0;
pub const MARGIN_TICKS: f64 = 0.2;
pub const MIN_BUFFER_TICKS: f64 = BASE_TICKS + MARGIN_TICKS;
pub const MAX_BUFFER_TICKS: f64 = 2.0;
pub const START_BUFFER_TICKS: f64 = MAX_BUFFER_TICKS;
pub const WIDEN_PER_SECOND: f64 = 2.0;
pub const NARROW_PER_SECOND: f64 = 0.5;
pub const JITTER_QUANTILE: f64 = 0.9;
pub const MAX_SAMPLES: usize = 32;
pub const GAP_TICKS: u64 = 8;
pub const SNAP_DISTANCE: f64 = 3.0;

/// Godot's `move_toward`.
fn move_toward(from: f64, to: f64, delta: f64) -> f64 {
    if (to - from).abs() <= delta {
        to
    } else {
        from + (to - from).signum() * delta
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct Sample {
    tick: u64,
    position: [f64; 3],
}

/// One timeline: its own clock, as `RemotePresentation` with no shared clock.
#[derive(Debug, Clone)]
pub struct Timeline {
    samples: VecDeque<Sample>,
    offsets: VecDeque<i64>,
    render_tick: f64,
    pub buffer_ticks: f64,
    adapted_usec: Option<i64>,
    /// The last `sample` wanted a tick newer than any received.
    pub starved: bool,
    /// A fixed buffer instead of the adaptive one: the client before #525
    /// drew every fighter two ticks behind.
    pinned: Option<f64>,
}

impl Default for Timeline {
    fn default() -> Self {
        Self {
            samples: VecDeque::new(),
            offsets: VecDeque::new(),
            render_tick: -1.0,
            buffer_ticks: START_BUFFER_TICKS,
            adapted_usec: None,
            starved: false,
            pinned: None,
        }
    }
}

/// What a frame draws: the fractional tick and the interpolated position.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Drawn {
    pub tick: f64,
    pub position: [f64; 3],
}

impl Timeline {
    /// A timeline that always draws `ticks` behind, for before and after
    /// comparisons over the same arrivals.
    pub fn pinned(ticks: f64) -> Self {
        Self {
            buffer_ticks: ticks,
            pinned: Some(ticks),
            ..Self::default()
        }
    }

    pub fn reset(&mut self) {
        *self = match self.pinned {
            Some(ticks) => Self::pinned(ticks),
            None => Self::default(),
        };
    }

    /// `accept` for a pose; returns false for a duplicate or older tick.
    pub fn accept(&mut self, tick: u64, position: [f64; 3], arrival_usec: i64) -> bool {
        if let Some(previous) = self.samples.back() {
            if tick <= previous.tick {
                return false;
            }
            let step = (0..3)
                .map(|i| (position[i] - previous.position[i]).powi(2))
                .sum::<f64>()
                .sqrt();
            if tick - previous.tick > GAP_TICKS || step > SNAP_DISTANCE {
                self.reset();
            }
        }
        if self.samples.is_empty() {
            self.render_tick = tick as f64;
        }
        self.samples.push_back(Sample { tick, position });
        self.offsets
            .push_back(arrival_usec - tick as i64 * TICK_USEC);
        while self.samples.len() > MAX_SAMPLES {
            self.samples.pop_front();
        }
        while self.offsets.len() > MAX_SAMPLES {
            self.offsets.pop_front();
        }
        true
    }

    /// `observe`: a clock-only snapshot.
    pub fn observe(&mut self, tick: u64, arrival_usec: i64) -> bool {
        self.accept(tick, [0.0; 3], arrival_usec)
    }

    pub fn target_buffer_ticks(&self) -> f64 {
        if let Some(ticks) = self.pinned {
            return ticks;
        }
        let Some(&base) = self.offsets.iter().min() else {
            return START_BUFFER_TICKS;
        };
        let mut late: Vec<i64> = self.offsets.iter().map(|o| o - base).collect();
        late.sort_unstable();
        let index = ((JITTER_QUANTILE * late.len() as f64).ceil() as usize)
            .saturating_sub(1)
            .min(late.len() - 1);
        (BASE_TICKS + MARGIN_TICKS + late[index] as f64 / TICK_USEC as f64)
            .clamp(MIN_BUFFER_TICKS, MAX_BUFFER_TICKS)
    }

    /// `desired_tick`: the tick wanted now, slewing the buffer; None before
    /// any arrival.
    pub fn desired_tick(&mut self, now_usec: i64) -> Option<f64> {
        let offset = *self.offsets.iter().min()?;
        let elapsed = self
            .adapted_usec
            .map_or(0.0, |at| (now_usec - at).max(0) as f64 / 1_000_000.0);
        self.adapted_usec = Some(self.adapted_usec.map_or(now_usec, |at| at.max(now_usec)));
        let target = self.target_buffer_ticks();
        let rate = if target > self.buffer_ticks {
            WIDEN_PER_SECOND
        } else {
            NARROW_PER_SECOND
        };
        self.buffer_ticks = move_toward(self.buffer_ticks, target, rate * elapsed);
        Some((now_usec - offset) as f64 / TICK_USEC as f64 - self.buffer_ticks)
    }

    /// `sample`: what a frame at `now_usec` draws, or None with no history.
    pub fn sample(&mut self, now_usec: i64) -> Option<Drawn> {
        let desired = self.desired_tick(now_usec)?;
        let (oldest, newest) = (self.samples.front()?.tick, self.samples.back()?.tick);
        self.starved = desired > newest as f64;
        self.render_tick = self
            .render_tick
            .max(desired)
            .clamp(oldest as f64, newest as f64);
        let render = self.render_tick;
        let pairs = self.samples.iter().zip(self.samples.iter().skip(1));
        for (previous, next) in pairs {
            if (next.tick as f64) < render {
                continue;
            }
            let weight = ((render - previous.tick as f64) / (next.tick - previous.tick) as f64)
                .clamp(0.0, 1.0);
            let position = std::array::from_fn(|i| {
                previous.position[i] + (next.position[i] - previous.position[i]) * weight
            });
            return Some(Drawn {
                tick: render,
                position,
            });
        }
        let last = self.samples.back()?;
        Some(Drawn {
            tick: render,
            position: last.position,
        })
    }
}

/// One golden case: the clock fed arrivals and sampled at frames.
#[derive(Debug, Clone, Serialize)]
pub struct GoldenCase {
    pub name: &'static str,
    /// `[tick, arrival_usec]` for each snapshot, in arrival order.
    pub arrivals: Vec<[i64; 2]>,
    /// `[now_usec, view_tick, buffer_ticks]` at each frame.
    pub frames: Vec<[f64; 3]>,
}

/// Small seeded stream for the golden arrivals.
fn draw(state: &mut u64, below: u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state % below
}

/// Snapshots of every tick from 100 for `seconds`, arriving at their tick
/// plus `late(tick)` microseconds and never before the previous one, with
/// frames every `frame_usec` sampled between them.
fn case(
    name: &'static str,
    seconds: i64,
    frame_usec: i64,
    mut late: impl FnMut(u64) -> i64,
) -> GoldenCase {
    let start = 5_000_000i64;
    let ticks = (seconds * 1_000_000 / TICK_USEC) as u64;
    let mut arrivals = Vec::new();
    let mut previous = 0i64;
    for index in 0..ticks {
        let tick = 100 + index;
        let at = (start + index as i64 * TICK_USEC + 3_000 + late(tick)).max(previous);
        previous = at;
        arrivals.push([tick as i64, at]);
    }
    let mut clock = Timeline::default();
    let mut frames = Vec::new();
    let mut next = 0usize;
    let mut now = start;
    let end = start + seconds * 1_000_000;
    while now < end {
        while next < arrivals.len() && arrivals[next][1] <= now {
            clock.observe(arrivals[next][0] as u64, arrivals[next][1]);
            next += 1;
        }
        if let Some(drawn) = clock.sample(now) {
            frames.push([now as f64, drawn.tick, clock.buffer_ticks]);
        }
        now += frame_usec;
    }
    GoldenCase {
        name,
        arrivals,
        frames,
    }
}

/// The cases the golden file holds.
pub fn golden_cases() -> Vec<GoldenCase> {
    let mut jitter = 0x2545_F491u64;
    let mut burst = 0x9E37_79B9u64;
    vec![
        case("steady_60fps", 4, 16_667, |_| 0),
        case("steady_144fps", 3, 6_944, |_| 0),
        case("jitter_20ms_60fps", 4, 16_667, move |_| {
            draw(&mut jitter, 20_001) as i64
        }),
        // A 250 ms stall at 1.5 s, then a calm link: widen, hold, narrow.
        case("stall_then_calm_60fps", 6, 16_667, move |tick| {
            let extra = if tick == 130 { 250_000 } else { 0 };
            extra + draw(&mut burst, 2_001) as i64
        }),
    ]
}

pub const GOLDEN_PATH: &str = "client/golden/presentation_vectors.json";
pub const GOLDEN_VERSION: u32 = 1;

pub fn golden_json() -> serde_json::Value {
    serde_json::json!({
        "version": GOLDEN_VERSION,
        "constants": {
            "tick_usec": TICK_USEC,
            "min_buffer_ticks": MIN_BUFFER_TICKS,
            "max_buffer_ticks": MAX_BUFFER_TICKS,
            "start_buffer_ticks": START_BUFFER_TICKS,
            "widen_per_second": WIDEN_PER_SECOND,
            "narrow_per_second": NARROW_PER_SECOND,
            "jitter_quantile": JITTER_QUANTILE,
            "max_samples": MAX_SAMPLES,
        },
        "cases": golden_cases(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn workspace_path(relative: &str) -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join(relative)
    }

    #[test]
    fn the_committed_golden_matches_the_model() {
        let path = workspace_path(GOLDEN_PATH);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| {
            panic!(
                "read {}: {e}; regenerate with the ignored test",
                path.display()
            )
        });
        let committed: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(
            committed,
            golden_json(),
            "presentation model changed; regenerate {GOLDEN_PATH} with `cargo test -p fragr-playtest --lib regenerate_presentation_golden -- --ignored` and replay it in Godot"
        );
    }

    #[test]
    #[ignore]
    fn regenerate_presentation_golden() {
        let json = serde_json::to_string_pretty(&golden_json()).unwrap();
        std::fs::write(workspace_path(GOLDEN_PATH), format!("{json}\n")).unwrap();
    }

    fn settled_buffer(case: &GoldenCase) -> f64 {
        case.frames.last().unwrap()[2]
    }

    #[test]
    fn a_steady_link_settles_one_tick_and_a_margin_behind() {
        let cases = golden_cases();
        for case in &cases[..2] {
            assert_eq!(settled_buffer(case), MIN_BUFFER_TICKS, "{}", case.name);
            // Drawn time never runs backwards, never jumps a frame's worth
            // past what time allows, and the newest snapshot always leads.
            for pair in case.frames.windows(2) {
                let advance = pair[1][1] - pair[0][1];
                let wall = (pair[1][0] - pair[0][0]) / TICK_USEC as f64;
                assert!(advance >= 0.0, "{}: {pair:?}", case.name);
                assert!(advance <= wall * 1.03 + 1e-9, "{}: {pair:?}", case.name);
            }
        }
        // 20 ms of jitter: wider, but under two ticks.
        let jitter = settled_buffer(&cases[2]);
        assert!(
            jitter > MIN_BUFFER_TICKS + 0.2 && jitter < MAX_BUFFER_TICKS,
            "{jitter}"
        );
    }

    #[test]
    fn a_stall_widens_the_buffer_and_a_calm_link_narrows_it_again() {
        let stall = &golden_cases()[3];
        let at = |usec: f64| {
            stall
                .frames
                .iter()
                .find(|frame| frame[0] >= usec)
                .map(|frame| frame[2])
                .unwrap()
        };
        let before = at(5_000_000.0 + 1_400_000.0);
        let during = at(5_000_000.0 + 2_500_000.0);
        let after = settled_buffer(stall);
        assert!(before < 1.35, "{before}");
        assert!(during > 1.9, "{during}");
        assert!(after < 1.35, "{after}");
    }

    #[test]
    fn timelines_refuse_old_ticks_and_reset_on_gaps_and_teleports() {
        let mut timeline = Timeline::default();
        assert!(timeline.sample(0).is_none());
        assert!(timeline.accept(10, [0.0; 3], 500_000));
        assert!(!timeline.accept(10, [1.0, 0.0, 0.0], 550_000));
        assert!(timeline.accept(11, [1.0, 0.0, 0.0], 550_000));
        assert_eq!(timeline.sample(550_000).unwrap().tick, 10.0);
        assert!(timeline.accept(12, [9.0, 0.0, 0.0], 600_000));
        assert_eq!(timeline.samples.len(), 1, "a teleport starts again");
        assert!(timeline.accept(40, [9.0, 0.0, 0.0], 2_000_000));
        assert_eq!(timeline.samples.len(), 1, "a gap starts again");
        let drawn = timeline.sample(9_000_000).unwrap();
        assert!(timeline.starved && drawn.position == [9.0, 0.0, 0.0]);
        let mut before = Timeline::pinned(2.0);
        before.accept(10, [0.0; 3], 500_000);
        before.accept(11, [1.0, 0.0, 0.0], 550_000);
        assert_eq!(before.sample(650_000).unwrap().tick, 11.0);
        before.reset();
        assert_eq!(before.target_buffer_ticks(), 2.0);
        assert_eq!(move_toward(1.0, 2.0, 0.25), 1.25);
        assert_eq!(move_toward(1.0, 0.9, 0.25), 0.9);
    }
}
