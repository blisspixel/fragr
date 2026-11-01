//! Loudness and true peak of rendered audio, measured the ITU-R BS.1770-4 way
//! with EBU R128 gating (EBU Tech 3341 and 3342).
//!
//! Local and free: it reads WAV files and touches nothing else. It exists so
//! the game's mix target (-23 to -18 LUFS integrated, true peak at or below
//! -1 dBTP; `docs/plans/fun-craft-targets.md` row 19) is a number a check can
//! read from QA tour captures, not an opinion. Written here rather than pulled
//! in as a crate: the measurement is a few hundred lines of arithmetic, the
//! workspace keeps its dependency list short, and the tests pin it against the
//! EBU reference signals.
//!
//! - K weighting: the BS.1770 two-stage pre-filter (high shelf, then high
//!   pass), with coefficients derived for any sample rate.
//! - Momentary loudness: 400 ms blocks every 100 ms. Short-term: 3 s windows
//!   every 100 ms.
//! - Integrated loudness: blocks gated at -70 LUFS absolute, then at 10 LU
//!   under the mean of the survivors.
//! - Loudness range: short-term values gated at -70 LUFS and 20 LU under their
//!   mean; the spread from the 10th to the 95th percentile.
//! - True peak: 4x oversampled (2x at 96 kHz and above) through a windowed
//!   sinc interpolator, as BS.1770-4 Annex 2 describes.

use crate::Error;
use serde::Serialize;
use std::path::Path;

/// The BS.1770 offset that makes a full-scale 997 Hz sine read -3.01 LUFS
/// per channel.
const LOUDNESS_OFFSET: f64 = -0.691;
/// EBU R128 absolute gate.
pub const ABSOLUTE_GATE_LUFS: f64 = -70.0;
/// Integrated loudness relative gate under the ungated mean.
const RELATIVE_GATE_LU: f64 = -10.0;
/// Loudness range relative gate (EBU Tech 3342).
const RANGE_GATE_LU: f64 = -20.0;
/// Interpolator half length in input samples per side.
const SINC_HALF_TAPS: usize = 12;

/// Samples as floats in [-1, 1], interleaved by channel.
#[derive(Debug, Clone, PartialEq)]
pub struct Pcm {
    pub sample_rate: u32,
    pub channels: u16,
    pub samples: Vec<f64>,
}

impl Pcm {
    pub fn frames(&self) -> usize {
        if self.channels == 0 {
            0
        } else {
            self.samples.len() / usize::from(self.channels)
        }
    }

    pub fn seconds(&self) -> f64 {
        self.frames() as f64 / f64::from(self.sample_rate.max(1))
    }
}

/// What a measurement reports. Loudness values are LUFS, ranges LU, peaks dB
/// relative to full scale. A value that cannot exist (silence, a clip shorter
/// than one block) is `None` and prints as such, never as a made-up floor.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Loudness {
    pub file: String,
    pub sample_rate: u32,
    pub channels: u16,
    pub seconds: f64,
    pub integrated_lufs: Option<f64>,
    pub loudness_range_lu: Option<f64>,
    pub momentary_max_lufs: Option<f64>,
    pub short_term_max_lufs: Option<f64>,
    pub sample_peak_dbfs: Option<f64>,
    pub true_peak_dbtp: Option<f64>,
}

/// Bounds a measurement must meet, for a pass or fail exit.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Target {
    pub integrated_min: f64,
    pub integrated_max: f64,
    pub true_peak_max: f64,
}

impl Target {
    /// The desktop gameplay target from the 1.0 bar.
    pub const GAMEPLAY: Target = Target {
        integrated_min: -23.0,
        integrated_max: -18.0,
        true_peak_max: -1.0,
    };

    /// Each reason the measurement misses, empty when it passes.
    pub fn misses(&self, loudness: &Loudness) -> Vec<String> {
        let mut out = Vec::new();
        match loudness.integrated_lufs {
            None => out.push("no gated loudness (silent or shorter than 400 ms)".to_string()),
            Some(value) if value < self.integrated_min || value > self.integrated_max => {
                out.push(format!(
                    "integrated {value:.1} LUFS outside {:.1} to {:.1}",
                    self.integrated_min, self.integrated_max
                ))
            }
            Some(_) => {}
        }
        if let Some(peak) = loudness.true_peak_dbtp {
            if peak > self.true_peak_max {
                out.push(format!(
                    "true peak {peak:.2} dBTP above {:.1}",
                    self.true_peak_max
                ));
            }
        }
        out
    }
}

/// Read a RIFF WAVE file: integer PCM at 8, 16, 24 or 32 bits, or 32 and 64
/// bit IEEE float, any channel count. Anything else is refused by name.
pub fn read_wav(bytes: &[u8]) -> Result<Pcm, Error> {
    let bad = |why: &str| Error::InvalidArgument(format!("not a readable WAV file: {why}"));
    if bytes.len() < 12 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return Err(bad("missing RIFF/WAVE header"));
    }
    let mut format: Option<(u16, u16, u32, u16)> = None;
    let mut data: Option<&[u8]> = None;
    let mut at = 12;
    while at + 8 <= bytes.len() {
        let id = &bytes[at..at + 4];
        let size = u32::from_le_bytes([bytes[at + 4], bytes[at + 5], bytes[at + 6], bytes[at + 7]])
            as usize;
        let body_start = at + 8;
        // A writer that stopped early may leave a short final chunk; take what is there.
        let body_end = body_start.saturating_add(size).min(bytes.len());
        let body = &bytes[body_start..body_end];
        if id == b"fmt " {
            if body.len() < 16 {
                return Err(bad("short fmt chunk"));
            }
            let mut tag = u16::from_le_bytes([body[0], body[1]]);
            let channels = u16::from_le_bytes([body[2], body[3]]);
            let rate = u32::from_le_bytes([body[4], body[5], body[6], body[7]]);
            let bits = u16::from_le_bytes([body[14], body[15]]);
            if tag == 0xFFFE && body.len() >= 26 {
                // WAVE_FORMAT_EXTENSIBLE: the real tag opens the sub-format GUID.
                tag = u16::from_le_bytes([body[24], body[25]]);
            }
            format = Some((tag, channels, rate, bits));
        } else if id == b"data" {
            data = Some(body);
        }
        at = body_start.saturating_add(size).saturating_add(size & 1);
    }
    let (tag, channels, sample_rate, bits) = format.ok_or_else(|| bad("no fmt chunk"))?;
    let data = data.ok_or_else(|| bad("no data chunk"))?;
    if channels == 0 || !(8_000..=768_000).contains(&sample_rate) {
        return Err(bad("channel count or sample rate out of range"));
    }
    let width = usize::from(bits / 8);
    let samples: Vec<f64> = match (tag, bits) {
        (1, 8) => data
            .iter()
            .map(|b| (f64::from(*b) - 128.0) / 128.0)
            .collect(),
        (1, 16) => data
            .as_chunks::<2>()
            .0
            .iter()
            .map(|c| f64::from(i16::from_le_bytes([c[0], c[1]])) / 32_768.0)
            .collect(),
        (1, 24) => data
            .as_chunks::<3>()
            .0
            .iter()
            .map(|c| f64::from(i32::from_le_bytes([0, c[0], c[1], c[2]]) >> 8) / 8_388_608.0)
            .collect(),
        (1, 32) => data
            .as_chunks::<4>()
            .0
            .iter()
            .map(|c| f64::from(i32::from_le_bytes([c[0], c[1], c[2], c[3]])) / 2_147_483_648.0)
            .collect(),
        (3, 32) => data
            .as_chunks::<4>()
            .0
            .iter()
            .map(|c| f64::from(f32::from_le_bytes([c[0], c[1], c[2], c[3]])))
            .collect(),
        (3, 64) => data
            .as_chunks::<8>()
            .0
            .iter()
            .map(|c| f64::from_le_bytes([c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]]))
            .collect(),
        _ => {
            return Err(bad(&format!(
                "unsupported encoding (tag {tag}, {bits} bits)"
            )))
        }
    };
    debug_assert!(width > 0);
    let whole = samples.len() - samples.len() % usize::from(channels);
    let mut samples = samples;
    samples.truncate(whole);
    if samples.iter().any(|s| !s.is_finite()) {
        return Err(bad("non-finite sample"));
    }
    Ok(Pcm {
        sample_rate,
        channels,
        samples,
    })
}

pub fn measure_file(path: &Path) -> Result<Loudness, Error> {
    let bytes = std::fs::read(path)?;
    let pcm = read_wav(&bytes)?;
    Ok(measure(&pcm, &path.display().to_string()))
}

/// One second-order section in direct form I.
#[derive(Debug, Clone, Copy)]
struct Biquad {
    b: [f64; 3],
    a: [f64; 2],
}

/// The BS.1770 K-weighting pre-filter, both stages, for `rate`. The analogue
/// prototypes (shelf at 1681.97 Hz, +4 dB; high pass at 38.14 Hz) are mapped
/// with the bilinear transform, which reproduces the published 48 kHz
/// coefficients and stays correct at 44.1 kHz.
fn k_weighting(rate: u32) -> [Biquad; 2] {
    let fs = f64::from(rate);
    let (f0, gain_db, q) = (
        1_681.974_450_955_533,
        3.999_843_853_973_347,
        0.707_175_236_955_419_6,
    );
    let k = (std::f64::consts::PI * f0 / fs).tan();
    let vh = 10f64.powf(gain_db / 20.0);
    let vb = vh.powf(0.499_666_774_154_541_6);
    let a0 = 1.0 + k / q + k * k;
    let shelf = Biquad {
        b: [
            (vh + vb * k / q + k * k) / a0,
            2.0 * (k * k - vh) / a0,
            (vh - vb * k / q + k * k) / a0,
        ],
        a: [2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0],
    };
    let (f0, q) = (38.135_470_876_024_44, 0.500_327_037_323_877_3);
    let k = (std::f64::consts::PI * f0 / fs).tan();
    let a0 = 1.0 + k / q + k * k;
    let high_pass = Biquad {
        b: [1.0, -2.0, 1.0],
        a: [2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0],
    };
    [shelf, high_pass]
}

/// BS.1770 channel weights: 1.0 for left, right and centre, 0 for the LFE of
/// a 5.1 layout, 1.41 for its surrounds.
fn channel_weight(channel: usize, channels: usize) -> f64 {
    if channels == 6 {
        match channel {
            3 => 0.0,
            4 | 5 => 1.41,
            _ => 1.0,
        }
    } else {
        1.0
    }
}

fn to_lufs(power: f64) -> Option<f64> {
    (power > 0.0).then(|| LOUDNESS_OFFSET + 10.0 * power.log10())
}

/// Weighted mean-square power of K-filtered audio over windows of `window`
/// frames, one every `step` frames. A clip shorter than one window has none.
fn window_powers(filtered: &[Vec<f64>], weights: &[f64], window: usize, step: usize) -> Vec<f64> {
    let frames = filtered.first().map_or(0, Vec::len);
    if window == 0 || frames < window {
        return Vec::new();
    }
    // Prefix sums of the weighted squared signal make every window O(1).
    let mut prefix = vec![0.0f64; frames + 1];
    for frame in 0..frames {
        let mut sum = 0.0;
        for (channel, data) in filtered.iter().enumerate() {
            sum += weights[channel] * data[frame] * data[frame];
        }
        prefix[frame + 1] = prefix[frame] + sum;
    }
    let mut out = Vec::new();
    let mut start = 0;
    while start + window <= frames {
        out.push(((prefix[start + window] - prefix[start]) / window as f64).max(0.0));
        start += step;
    }
    out
}

fn mean(values: &[f64]) -> Option<f64> {
    (!values.is_empty()).then(|| values.iter().sum::<f64>() / values.len() as f64)
}

/// Gated integrated loudness over 400 ms block powers.
fn integrated(blocks: &[f64]) -> Option<f64> {
    let gate = 10f64.powf((ABSOLUTE_GATE_LUFS - LOUDNESS_OFFSET) / 10.0);
    let loud: Vec<f64> = blocks.iter().copied().filter(|p| *p > gate).collect();
    let relative = to_lufs(mean(&loud)?)? + RELATIVE_GATE_LU;
    let relative = 10f64.powf((relative - LOUDNESS_OFFSET) / 10.0);
    let kept: Vec<f64> = loud.into_iter().filter(|p| *p > relative).collect();
    to_lufs(mean(&kept)?)
}

/// Loudness range over 3 s short-term powers (EBU Tech 3342).
fn loudness_range(short_term: &[f64]) -> Option<f64> {
    let gate = 10f64.powf((ABSOLUTE_GATE_LUFS - LOUDNESS_OFFSET) / 10.0);
    let loud: Vec<f64> = short_term.iter().copied().filter(|p| *p > gate).collect();
    let relative = to_lufs(mean(&loud)?)? + RANGE_GATE_LU;
    let relative = 10f64.powf((relative - LOUDNESS_OFFSET) / 10.0);
    let mut kept: Vec<f64> = loud
        .into_iter()
        .filter(|p| *p > relative)
        .filter_map(to_lufs)
        .collect();
    if kept.is_empty() {
        return None;
    }
    kept.sort_by(f64::total_cmp);
    let at = |share: f64| -> f64 {
        let index = ((kept.len() - 1) as f64 * share).round() as usize;
        kept[index.min(kept.len() - 1)]
    };
    Some(at(0.95) - at(0.10))
}

/// The highest absolute value of the signal reconstructed between samples.
fn true_peak(pcm: &Pcm) -> f64 {
    let channels = usize::from(pcm.channels);
    let frames = pcm.frames();
    let factor: usize = if pcm.sample_rate >= 96_000 { 2 } else { 4 };
    // One windowed sinc phase per oversampled point, cut off at the input
    // Nyquist. Phase 0 is the sample itself.
    let taps = 2 * SINC_HALF_TAPS;
    let mut phases = vec![vec![0.0f64; taps]; factor];
    for (phase, kernel) in phases.iter_mut().enumerate() {
        let offset = phase as f64 / factor as f64;
        let mut total = 0.0;
        for (tap, weight) in kernel.iter_mut().enumerate() {
            // Tap `tap` weights the input sample at (tap - half + 1) relative
            // to the current one; the output sits `offset` past it.
            let x = tap as f64 - SINC_HALF_TAPS as f64 + 1.0 - offset;
            let sinc = if x.abs() < 1e-12 {
                1.0
            } else {
                (std::f64::consts::PI * x).sin() / (std::f64::consts::PI * x)
            };
            let span = SINC_HALF_TAPS as f64;
            let window = if x.abs() >= span {
                0.0
            } else {
                0.5 + 0.5 * (std::f64::consts::PI * x / span).cos()
            };
            *weight = sinc * window;
            total += *weight;
        }
        if total.abs() > 1e-12 {
            for weight in kernel.iter_mut() {
                *weight /= total;
            }
        }
    }
    let mut peak = 0.0f64;
    for channel in 0..channels {
        let at = |frame: isize| -> f64 {
            if frame < 0 || frame as usize >= frames {
                0.0
            } else {
                pcm.samples[frame as usize * channels + channel]
            }
        };
        for frame in 0..frames {
            peak = peak.max(at(frame as isize).abs());
            for kernel in phases.iter().skip(1) {
                let mut value = 0.0;
                for (tap, weight) in kernel.iter().enumerate() {
                    value +=
                        weight * at(frame as isize + tap as isize - SINC_HALF_TAPS as isize + 1);
                }
                peak = peak.max(value.abs());
            }
        }
    }
    peak
}

fn db(linear: f64) -> Option<f64> {
    (linear > 0.0).then(|| 20.0 * linear.log10())
}

pub fn measure(pcm: &Pcm, file: &str) -> Loudness {
    let channels = usize::from(pcm.channels);
    let frames = pcm.frames();
    let filters = k_weighting(pcm.sample_rate);
    let mut filtered = vec![vec![0.0f64; frames]; channels];
    for (channel, out) in filtered.iter_mut().enumerate() {
        let mut signal: Vec<f64> = (0..frames)
            .map(|frame| pcm.samples[frame * channels + channel])
            .collect();
        for stage in filters {
            let (mut x1, mut x2, mut y1, mut y2) = (0.0, 0.0, 0.0, 0.0);
            for value in signal.iter_mut() {
                let x0 = *value;
                let y0 = stage.b[0] * x0 + stage.b[1] * x1 + stage.b[2] * x2
                    - stage.a[0] * y1
                    - stage.a[1] * y2;
                x2 = x1;
                x1 = x0;
                y2 = y1;
                y1 = y0;
                *value = y0;
            }
        }
        *out = signal;
    }
    let weights: Vec<f64> = (0..channels)
        .map(|channel| channel_weight(channel, channels))
        .collect();
    let rate = pcm.sample_rate as usize;
    let step = rate / 10;
    let blocks = window_powers(&filtered, &weights, rate * 4 / 10, step);
    let short_term = window_powers(&filtered, &weights, rate * 3, step);
    let sample_peak = pcm.samples.iter().fold(0.0f64, |peak, s| peak.max(s.abs()));
    let max_power = |powers: &[f64]| {
        powers.iter().copied().fold(None, |best: Option<f64>, p| {
            Some(best.map_or(p, |b| b.max(p)))
        })
    };
    Loudness {
        file: file.to_string(),
        sample_rate: pcm.sample_rate,
        channels: pcm.channels,
        seconds: pcm.seconds(),
        integrated_lufs: integrated(&blocks),
        loudness_range_lu: loudness_range(&short_term),
        momentary_max_lufs: max_power(&blocks).and_then(to_lufs),
        short_term_max_lufs: max_power(&short_term).and_then(to_lufs),
        sample_peak_dbfs: db(sample_peak),
        true_peak_dbtp: db(true_peak(pcm)),
    }
}

fn shown(value: Option<f64>, unit: &str) -> String {
    value.map_or_else(|| "none".to_string(), |v| format!("{v:.1} {unit}"))
}

/// One line per file, as a person reads it.
pub fn describe(loudness: &Loudness) -> String {
    format!(
        "{}: {:.1} s, {} Hz x{}, integrated {}, range {}, momentary max {}, short-term max {}, sample peak {}, true peak {}",
        loudness.file,
        loudness.seconds,
        loudness.sample_rate,
        loudness.channels,
        shown(loudness.integrated_lufs, "LUFS"),
        shown(loudness.loudness_range_lu, "LU"),
        shown(loudness.momentary_max_lufs, "LUFS"),
        shown(loudness.short_term_max_lufs, "LUFS"),
        shown(loudness.sample_peak_dbfs, "dBFS"),
        shown(loudness.true_peak_dbtp, "dBTP"),
    )
}

/// A clip brought to a loudness for an asset set: summed to mono (the
/// game places it in the world, so its own stereo image would fight the
/// panning), then scaled so its loudest 400 ms block reads `target_lufs`,
/// unless that would push the true peak over `peak_ceiling_dbtp`, in which
/// case the peak decides. Returns the levelled clip and the gain used.
pub fn level(pcm: &Pcm, target_lufs: f64, peak_ceiling_dbtp: f64) -> Option<(Pcm, f64)> {
    let channels = usize::from(pcm.channels);
    if channels == 0 {
        return None;
    }
    let mono = Pcm {
        sample_rate: pcm.sample_rate,
        channels: 1,
        samples: pcm
            .samples
            .chunks_exact(channels)
            .map(|frame| frame.iter().sum::<f64>() / channels as f64)
            .collect(),
    };
    let measured = measure(&mono, "");
    // A clip shorter than one block is measured as one block of itself.
    let loudness = measured.momentary_max_lufs.or_else(|| {
        let mut padded = mono.clone();
        let block = mono.sample_rate as usize * 4 / 10;
        padded.samples.resize(block.max(mono.samples.len()), 0.0);
        measure(&padded, "").momentary_max_lufs
    })?;
    let peak = measured.true_peak_dbtp?;
    let gain = (target_lufs - loudness).min(peak_ceiling_dbtp - peak);
    let scale = 10f64.powf(gain / 20.0);
    let samples = mono.samples.iter().map(|s| s * scale).collect();
    Some((Pcm { samples, ..mono }, gain))
}

/// 16-bit PCM WAV bytes for a clip, rounded and clamped to full scale.
pub fn to_wav16(pcm: &Pcm) -> Vec<u8> {
    let mut body = Vec::with_capacity(pcm.samples.len() * 2);
    for sample in &pcm.samples {
        let value = (sample * 32_767.0).round().clamp(-32_768.0, 32_767.0) as i16;
        body.extend_from_slice(&value.to_le_bytes());
    }
    crate::wav_from_pcm_s16le(&body, pcm.sample_rate, pcm.channels)
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: u32 = 48_000;

    /// A stereo sine with both channels at `dbfs` peak for `seconds`.
    fn sine(frequency: f64, dbfs: f64, seconds: f64, rate: u32) -> Vec<f64> {
        let amplitude = 10f64.powf(dbfs / 20.0);
        let frames = (seconds * f64::from(rate)) as usize;
        let mut out = Vec::with_capacity(frames * 2);
        for frame in 0..frames {
            let value = amplitude
                * (2.0 * std::f64::consts::PI * frequency * frame as f64 / f64::from(rate)).sin();
            out.push(value);
            out.push(value);
        }
        out
    }

    fn stereo(samples: Vec<f64>, rate: u32) -> Pcm {
        Pcm {
            sample_rate: rate,
            channels: 2,
            samples,
        }
    }

    fn wav16(pcm: &Pcm) -> Vec<u8> {
        to_wav16(pcm)
    }

    #[test]
    fn the_ebu_reference_sine_reads_minus_23() {
        // EBU Tech 3341 case 1: 1 kHz stereo at -23 dBFS reads -23.0 LUFS.
        for rate in [44_100, 48_000] {
            let result = measure(&stereo(sine(1_000.0, -23.0, 20.0, rate), rate), "case1");
            let value = result.integrated_lufs.unwrap();
            assert!((value + 23.0).abs() < 0.1, "{rate} Hz read {value}");
            assert!((result.momentary_max_lufs.unwrap() + 23.0).abs() < 0.1);
            assert!((result.short_term_max_lufs.unwrap() + 23.0).abs() < 0.1);
            // A steady tone has no loudness range.
            assert!(result.loudness_range_lu.unwrap() < 0.1);
        }
        // Case 2: -33 dBFS reads -33.0.
        let value = measure(&stereo(sine(1_000.0, -33.0, 20.0, RATE), RATE), "case2")
            .integrated_lufs
            .unwrap();
        assert!((value + 33.0).abs() < 0.1, "{value}");
    }

    #[test]
    fn the_relative_gate_ignores_quiet_passages() {
        // EBU Tech 3341 case 3: 10 s at -36, 60 s at -23, 10 s at -36 reads -23.0.
        let mut samples = sine(1_000.0, -36.0, 10.0, RATE);
        samples.extend(sine(1_000.0, -23.0, 60.0, RATE));
        samples.extend(sine(1_000.0, -36.0, 10.0, RATE));
        let value = measure(&stereo(samples, RATE), "case3")
            .integrated_lufs
            .unwrap();
        assert!((value + 23.0).abs() < 0.1, "{value}");
        // Case 5: -26, then -20, then -26 (20.1 s each) reads -23.0 too.
        let mut samples = sine(1_000.0, -26.0, 20.0, RATE);
        samples.extend(sine(1_000.0, -20.0, 20.1, RATE));
        samples.extend(sine(1_000.0, -26.0, 20.0, RATE));
        let value = measure(&stereo(samples, RATE), "case5")
            .integrated_lufs
            .unwrap();
        assert!((value + 23.0).abs() < 0.1, "{value}");
    }

    #[test]
    fn the_absolute_gate_drops_silence() {
        // Case 4: -72 dBFS, -36, -23, -36, -72 (10, 10, 60, 10, 10 s) reads -23.0.
        let mut samples = sine(1_000.0, -72.0, 10.0, RATE);
        samples.extend(sine(1_000.0, -36.0, 10.0, RATE));
        samples.extend(sine(1_000.0, -23.0, 60.0, RATE));
        samples.extend(sine(1_000.0, -36.0, 10.0, RATE));
        samples.extend(sine(1_000.0, -72.0, 10.0, RATE));
        let value = measure(&stereo(samples, RATE), "case4")
            .integrated_lufs
            .unwrap();
        assert!((value + 23.0).abs() < 0.1, "{value}");
        let silent = measure(&stereo(vec![0.0; RATE as usize * 4], RATE), "silence");
        assert_eq!(silent.integrated_lufs, None);
        assert_eq!(silent.true_peak_dbtp, None);
        let short = measure(&stereo(sine(1_000.0, -20.0, 0.3, RATE), RATE), "short");
        assert_eq!(short.integrated_lufs, None, "under one 400 ms block");
        assert_eq!(short.short_term_max_lufs, None);
    }

    #[test]
    fn loudness_range_reads_the_ebu_steps() {
        // EBU Tech 3342 case 1: 20 s at -20 then 20 s at -30 LUFS reads 10 LU.
        let mut samples = sine(1_000.0, -20.0, 20.0, RATE);
        samples.extend(sine(1_000.0, -30.0, 20.0, RATE));
        let range = measure(&stereo(samples, RATE), "lra1")
            .loudness_range_lu
            .unwrap();
        assert!((range - 10.0).abs() < 1.0, "{range}");
    }

    #[test]
    fn true_peak_finds_the_peak_between_samples() {
        // A quarter-rate sine sampled 45 degrees off its crest: every sample
        // sits 3 dB under the true peak.
        let frames = RATE as usize;
        let amplitude = 10f64.powf(-6.0 / 20.0);
        let mut samples = Vec::with_capacity(frames * 2);
        for frame in 0..frames {
            let value = amplitude
                * (std::f64::consts::FRAC_PI_2 * frame as f64 + std::f64::consts::FRAC_PI_4).sin();
            samples.push(value);
            samples.push(value);
        }
        let result = measure(&stereo(samples, RATE), "isp");
        let sample_peak = result.sample_peak_dbfs.unwrap();
        let true_peak = result.true_peak_dbtp.unwrap();
        assert!((sample_peak + 9.01).abs() < 0.05, "{sample_peak}");
        assert!((true_peak + 6.0).abs() < 0.4, "{true_peak}");
        // A slow sine has no hidden peak.
        let slow = measure(&stereo(sine(100.0, -1.0, 1.0, RATE), RATE), "slow");
        assert!((slow.true_peak_dbtp.unwrap() + 1.0).abs() < 0.05);
    }

    #[test]
    fn wav_reading_round_trips_and_refuses_what_it_cannot_read() {
        let pcm = stereo(sine(1_000.0, -23.0, 2.0, 44_100), 44_100);
        let read = read_wav(&wav16(&pcm)).unwrap();
        assert_eq!((read.sample_rate, read.channels), (44_100, 2));
        assert_eq!(read.frames(), pcm.frames());
        assert!((read.seconds() - 2.0).abs() < 1e-9);
        let value = measure(&read, "16-bit").integrated_lufs.unwrap();
        assert!((value + 23.0).abs() < 0.1, "{value}");
        assert!(read_wav(b"RIFF\0\0\0\0WAVX").is_err());
        assert!(read_wav(b"short").is_err());
        let mut no_data = wav16(&pcm);
        no_data.truncate(36);
        assert!(read_wav(&no_data).is_err());
        // 24-bit and float encodings read the same signal.
        let mut wav24 = wav16(&pcm);
        wav24.truncate(44);
        let mut body = Vec::new();
        for sample in &pcm.samples {
            let value = (sample * 8_388_607.0).round() as i32;
            body.extend_from_slice(&value.to_le_bytes()[0..3]);
        }
        wav24[34] = 24;
        wav24[40..44].copy_from_slice(&(body.len() as u32).to_le_bytes());
        wav24.extend_from_slice(&body);
        let read24 = read_wav(&wav24).unwrap();
        assert!((read24.samples[10] - pcm.samples[10]).abs() < 1e-6);
        let mut float = wav16(&pcm);
        float.truncate(44);
        float[20] = 3;
        float[34] = 32;
        let mut body = Vec::new();
        for sample in &pcm.samples {
            body.extend_from_slice(&(*sample as f32).to_le_bytes());
        }
        float[40..44].copy_from_slice(&(body.len() as u32).to_le_bytes());
        float.extend_from_slice(&body);
        let read_float = read_wav(&float).unwrap();
        assert!((read_float.samples[10] - pcm.samples[10]).abs() < 1e-6);
        float[34] = 12;
        assert!(read_wav(&float).is_err(), "12-bit float is no encoding");
    }

    #[test]
    fn targets_name_each_miss() {
        let mut result = measure(&stereo(sine(1_000.0, -20.0, 5.0, RATE), RATE), "mix");
        assert!(Target::GAMEPLAY.misses(&result).is_empty(), "{result:?}");
        result.integrated_lufs = Some(-30.0);
        result.true_peak_dbtp = Some(-0.2);
        let misses = Target::GAMEPLAY.misses(&result);
        assert_eq!(misses.len(), 2, "{misses:?}");
        result.integrated_lufs = None;
        assert!(Target::GAMEPLAY.misses(&result)[0].contains("no gated loudness"));
        let line = describe(&result);
        assert!(
            line.contains("integrated none") && line.contains("true peak -0.2 dBTP"),
            "{line}"
        );
    }

    #[test]
    fn levelling_meets_the_loudness_unless_the_peak_says_stop() {
        let quiet = stereo(sine(1_000.0, -40.0, 0.5, RATE), RATE);
        let (levelled, gain) = level(&quiet, -18.0, -1.0).unwrap();
        assert_eq!(levelled.channels, 1, "summed to mono");
        let read = measure(&levelled, "levelled");
        assert!(
            (read.momentary_max_lufs.unwrap() + 18.0).abs() < 0.2,
            "{read:?}"
        );
        assert!(gain > 20.0);
        // A spike cannot be lifted past the true peak ceiling.
        let mut spike = vec![0.0; RATE as usize];
        spike[RATE as usize / 2] = 0.1;
        let (levelled, _) = level(
            &Pcm {
                sample_rate: RATE,
                channels: 1,
                samples: spike,
            },
            -18.0,
            -1.0,
        )
        .unwrap();
        let peak = measure(&levelled, "spike").true_peak_dbtp.unwrap();
        assert!((peak + 1.0).abs() < 0.05, "{peak}");
        // A clip under one block is measured as that block.
        let short = stereo(sine(1_000.0, -30.0, 0.2, RATE), RATE);
        assert!(level(&short, -18.0, -1.0).is_some());
        assert!(
            level(&stereo(vec![0.0; 4_000], RATE), -18.0, -1.0).is_none(),
            "silence has no level"
        );
        let round = read_wav(&to_wav16(&levelled)).unwrap();
        assert_eq!(round.channels, 1);
    }

    #[test]
    fn surround_weights_follow_bs1770() {
        assert_eq!(channel_weight(3, 6), 0.0);
        assert_eq!(channel_weight(4, 6), 1.41);
        assert_eq!(channel_weight(1, 2), 1.0);
        // One channel of a stereo pair at -23 dBFS reads 3 dB under both.
        let mut samples = sine(1_000.0, -23.0, 10.0, RATE);
        for pair in samples.as_chunks_mut::<2>().0 {
            pair[1] = 0.0;
        }
        let value = measure(&stereo(samples, RATE), "left")
            .integrated_lufs
            .unwrap();
        assert!((value + 26.01).abs() < 0.1, "{value}");
    }
}
