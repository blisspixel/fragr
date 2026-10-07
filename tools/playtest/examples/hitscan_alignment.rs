//! Compare actual client presentation samples with authoritative shot geometry.
use clap::Parser;
use fragr_server::combat::aimed_fighter_distance;
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io::Read, path::PathBuf};

#[derive(Parser)]
struct Args {
    input: PathBuf,
    output: PathBuf,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Samples {
    schema: u32,
    buffer_ticks: f32,
    frame_hz: u32,
    tick_usec: u32,
    samples: Vec<Sample>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Sample {
    distance_m: f32,
    speed_m_s: f32,
    snapshot_delay_ms: u32,
    input_delay_ms: u32,
    render_tick: f32,
    resolve_tick: u32,
    shown_feet: [f32; 3],
    current_feet: [f32; 3],
}

#[derive(Default, Serialize)]
struct Row {
    distance_m: f32,
    speed_m_s: f32,
    snapshot_delay_ms: u32,
    input_delay_ms: u32,
    samples: u32,
    shown_body_hits: u32,
    current_body_hits: u32,
    mean_displacement_m: f32,
    max_displacement_m: f32,
    max_age_ms: f32,
}

#[derive(Serialize)]
struct Report {
    schema: u32,
    scope: &'static str,
    buffer_ticks: f32,
    frame_hz: u32,
    tick_usec: u32,
    rows: Vec<Row>,
}

fn analyze(data: Samples) -> Result<Report, String> {
    if data.schema != 1
        || data.tick_usec != 50_000
        || data.frame_hz != 60
        || data.buffer_ticks != 2.0
        || data.samples.is_empty()
        || data.samples.len() > 20_000
    {
        return Err("unsupported or empty presentation sample contract".into());
    }
    let mut rows: BTreeMap<String, Row> = BTreeMap::new();
    for sample in data.samples {
        if !sample
            .shown_feet
            .iter()
            .chain(sample.current_feet.iter())
            .all(|v| v.is_finite() && v.abs() <= 1000.0)
            || !sample.render_tick.is_finite()
            || sample.render_tick < 0.0
            || sample.render_tick > sample.resolve_tick as f32
            || sample.resolve_tick > 10_000
            || ![5.0, 15.0, 30.0].contains(&sample.distance_m)
            || !sample.speed_m_s.is_finite()
            || !(0.0..=5.0).contains(&sample.speed_m_s)
            || ![0, 40, 80].contains(&sample.snapshot_delay_ms)
            || sample.input_delay_ms != sample.snapshot_delay_ms
            || (sample.shown_feet[0] - sample.distance_m).abs() > 0.001
            || (sample.current_feet[0] - sample.distance_m).abs() > 0.001
        {
            return Err("invalid presentation sample".into());
        }
        let eye = [0.0, fragr_server::movement::EYE_HEIGHT, 0.0];
        let shown_hit =
            aimed_fighter_distance(eye, sample.shown_feet, sample.shown_feet, 1000.0).is_some();
        let current_hit =
            aimed_fighter_distance(eye, sample.shown_feet, sample.current_feet, 1000.0).is_some();
        if !shown_hit {
            return Err("shown-body control ray missed".into());
        }
        let displacement = sample
            .shown_feet
            .iter()
            .zip(sample.current_feet)
            .map(|(a, b)| (a - b).powi(2))
            .sum::<f32>()
            .sqrt();
        let expected = (sample.resolve_tick as f32 - sample.render_tick) * sample.speed_m_s / 20.0;
        if (displacement - expected).abs() > 0.002
            || sample.shown_feet[1] != 0.0
            || sample.current_feet[1] != 0.0
        {
            return Err("sample trajectory disagrees with its clock and speed".into());
        }
        let key = format!(
            "{:05.1}/{:04.2}/{:03}",
            sample.distance_m, sample.speed_m_s, sample.snapshot_delay_ms
        );
        let row = rows.entry(key).or_insert_with(|| Row {
            distance_m: sample.distance_m,
            speed_m_s: sample.speed_m_s,
            snapshot_delay_ms: sample.snapshot_delay_ms,
            input_delay_ms: sample.input_delay_ms,
            ..Row::default()
        });
        row.samples += 1;
        row.shown_body_hits += u32::from(shown_hit);
        row.current_body_hits += u32::from(current_hit);
        row.mean_displacement_m += displacement;
        row.max_displacement_m = row.max_displacement_m.max(displacement);
        row.max_age_ms = row
            .max_age_ms
            .max((sample.resolve_tick as f32 - sample.render_tick) * 50.0);
    }
    let mut rows: Vec<Row> = rows.into_values().collect();
    for row in &mut rows {
        row.mean_displacement_m /= row.samples as f32;
    }
    Ok(Report {
        schema: 1,
        scope: "client transform and server ray diagnostic; no live network or combat",
        buffer_ticks: data.buffer_ticks,
        frame_hz: data.frame_hz,
        tick_usec: data.tick_usec,
        rows,
    })
}

fn run(args: Args) -> Result<(), Box<dyn std::error::Error>> {
    let mut bytes = Vec::new();
    std::fs::File::open(args.input)?
        .take(8 * 1024 * 1024 + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() > 8 * 1024 * 1024 {
        return Err("sample document exceeds 8 MiB".into());
    }
    let report = analyze(serde_json::from_slice(&bytes)?)?;
    std::fs::write(args.output, serde_json::to_vec_pretty(&report)?)?;
    println!(
        "hitscan_alignment: PASS {} measured rows",
        report.rows.len()
    );
    Ok(())
}

fn main() {
    if let Err(error) = run(Args::parse()) {
        eprintln!("hitscan_alignment: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn data(moving: bool) -> Samples {
        Samples {
            schema: 1,
            buffer_ticks: 2.0,
            frame_hz: 60,
            tick_usec: 50_000,
            samples: vec![Sample {
                distance_m: 15.0,
                speed_m_s: if moving { 5.0 } else { 0.0 },
                snapshot_delay_ms: 80,
                input_delay_ms: 80,
                render_tick: 20.0,
                resolve_tick: 26,
                shown_feet: [15.0, 0.0, 0.0],
                current_feet: [15.0, 0.0, if moving { 1.5 } else { 0.0 }],
            }],
        }
    }

    #[test]
    fn static_control_agrees_and_moving_target_exposes_server_now_miss() {
        let static_report = analyze(data(false)).unwrap();
        assert_eq!(static_report.rows[0].current_body_hits, 1);
        let moving = analyze(data(true)).unwrap();
        assert_eq!(moving.rows[0].shown_body_hits, 1);
        assert_eq!(moving.rows[0].current_body_hits, 0);
        assert_eq!(moving.rows[0].max_displacement_m, 1.5);
        assert_eq!(moving.rows[0].max_age_ms, 300.0);
    }

    #[test]
    fn malformed_timelines_and_nonfinite_geometry_are_not_measurements() {
        let mut input = data(false);
        input.samples[0].render_tick = 30.0;
        assert!(analyze(input).is_err());
        let mut input = data(false);
        input.samples[0].current_feet[1] = f32::NAN;
        assert!(analyze(input).is_err());
        let mut input = data(false);
        input.samples.clear();
        assert!(analyze(input).is_err());
    }
}
