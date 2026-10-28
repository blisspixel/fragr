//! What the server process costs while the traffic roster runs: CPU time,
//! kernel socket memory, its own tick trace, and the shape of the snapshots
//! it sends. Each probe names its source; a platform without it reports
//! nothing rather than a guess.

use fragr_server::tick_trace::TickTraceRecord;
use serde::Serialize;
use std::io::BufRead;
use std::path::Path;

/// CPU time the process has run, summed over its threads, in nanoseconds.
/// Linux `schedstat` only.
pub fn cpu_ns(pid: u32) -> Option<u64> {
    let tasks = std::fs::read_dir(format!("/proc/{pid}/task")).ok()?;
    let mut total = 0u64;
    for task in tasks.flatten() {
        // A thread can exit between the listing and this read; it has no
        // time left to add, and it does not make the process unreadable.
        let Ok(text) = std::fs::read_to_string(task.path().join("schedstat")) else {
            continue;
        };
        total = total.saturating_add(parse_schedstat(&text)?);
    }
    Some(total)
}

/// The first field of `/proc/<pid>/task/<tid>/schedstat`: time on a CPU.
pub fn parse_schedstat(text: &str) -> Option<u64> {
    text.split_whitespace().next()?.parse().ok()
}

/// Kernel memory held by the server's established sockets, from `ss -m`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize)]
pub struct SocketMemory {
    pub sockets: usize,
    /// Receive memory allocated (`r`).
    pub rmem_alloc: u64,
    /// Transmit memory allocated (`t`): sent but not yet acknowledged.
    pub wmem_alloc: u64,
    /// Bytes queued to send and not yet sent (`w`).
    pub wmem_queued: u64,
    /// Memory reserved ahead for the socket (`f`).
    pub fwd_alloc: u64,
    /// The largest single socket's `t` plus `w`.
    pub max_send_bytes: u64,
}

impl SocketMemory {
    pub fn total(&self) -> u64 {
        self.rmem_alloc + self.wmem_alloc + self.wmem_queued + self.fwd_alloc
    }
}

/// Sum every `skmem:(r..,rb..,t..,tb..,f..,w..,...)` block in `ss` output.
pub fn parse_skmem(text: &str) -> SocketMemory {
    let mut memory = SocketMemory::default();
    for block in text.split("skmem:(").skip(1) {
        let Some(fields) = block.split(')').next() else {
            continue;
        };
        memory.sockets += 1;
        let mut send = 0;
        for field in fields.split(',') {
            let digits = field.trim_start_matches(|c: char| c.is_ascii_alphabetic());
            let Ok(value) = digits.parse::<u64>() else {
                continue;
            };
            match &field[..field.len() - digits.len()] {
                "r" => memory.rmem_alloc += value,
                "t" => {
                    memory.wmem_alloc += value;
                    send += value;
                }
                "w" => {
                    memory.wmem_queued += value;
                    send += value;
                }
                "f" => memory.fwd_alloc += value,
                _ => {}
            }
        }
        memory.max_send_bytes = memory.max_send_bytes.max(send);
    }
    memory
}

/// The server's established sockets on `port`. Linux `ss` only.
pub fn socket_memory(port: u16) -> Result<SocketMemory, String> {
    if !cfg!(target_os = "linux") {
        return Err("socket memory is read with Linux ss".into());
    }
    let output = std::process::Command::new("ss")
        .args(["-tmnH", "state", "established"])
        .arg(format!("( sport = :{port} )"))
        .output()
        .map_err(|error| format!("ss did not run: {error}"))?;
    if !output.status.success() {
        return Err(format!("ss exited with {}", output.status));
    }
    Ok(parse_skmem(&String::from_utf8_lossy(&output.stdout)))
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Spread {
    pub samples: usize,
    pub p50: f64,
    pub p99: f64,
    pub max: f64,
}

impl Spread {
    pub fn of(values: &mut [f64]) -> Self {
        values.sort_by(f64::total_cmp);
        let pick = |fraction: f64| {
            values
                .get(((values.len().saturating_sub(1)) as f64 * fraction).round() as usize)
                .copied()
                .unwrap_or_default()
        };
        Self {
            samples: values.len(),
            p50: pick(0.5),
            p99: pick(0.99),
            max: values.last().copied().unwrap_or_default(),
        }
    }
}

/// The server's own tick trace over the held window, in milliseconds.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct TickWindow {
    pub ticks: usize,
    /// Handlers at or above the 50 ms budget.
    pub over_budget: usize,
    /// Whole periods the loop skipped because it fell behind.
    pub skipped_periods: u64,
    pub queue_overflows: u64,
    /// Handler start after its scheduled deadline.
    pub late_ms: Spread,
    pub total_ms: Spread,
    pub sim_ms: Spread,
    /// Encoding each broadcast once.
    pub encode_ms: Spread,
    /// Queuing broadcasts and unicasts for every connection.
    pub fanout_ms: Spread,
    /// Mean broadcast bytes per tick before fan-out.
    pub bytes_per_tick: f64,
}

/// Read the trace and keep ticks `from..=to`. A trace cut by the harness's
/// stop has no footer; every flushed tick is still read.
pub fn tick_window(path: &Path, from: u64, to: u64) -> Result<TickWindow, String> {
    let file = std::fs::File::open(path).map_err(|error| format!("{}: {error}", path.display()))?;
    let mut samples = Vec::new();
    for line in std::io::BufReader::new(file).lines() {
        let line = line.map_err(|error| error.to_string())?;
        if line.is_empty() {
            continue;
        }
        match serde_json::from_str::<TickTraceRecord>(&line) {
            Ok(TickTraceRecord::Tick(sample)) if (from..=to).contains(&sample.tick) => {
                samples.push(sample);
            }
            Ok(_) => {}
            // The last line can be half written when the process is stopped.
            Err(_) => break,
        }
    }
    if samples.is_empty() {
        return Err(format!("no traced ticks from {from} to {to}"));
    }
    let ms = |pick: fn(&fragr_server::tick_trace::TickSample) -> u64| -> Spread {
        let mut values: Vec<f64> = samples.iter().map(|s| pick(s) as f64 / 1000.0).collect();
        Spread::of(&mut values)
    };
    let budget = std::time::Duration::from_millis(50);
    Ok(TickWindow {
        ticks: samples.len(),
        over_budget: samples.iter().filter(|s| s.over_budget(budget)).count(),
        skipped_periods: samples.iter().map(|s| s.skipped).sum(),
        queue_overflows: samples.iter().map(|s| s.overflows).sum(),
        late_ms: ms(|s| s.late_us),
        total_ms: ms(|s| s.total_us),
        sim_ms: ms(|s| s.sim_us),
        encode_ms: ms(|s| s.measure_us),
        fanout_ms: ms(|s| s.fanout_us),
        bytes_per_tick: samples.iter().map(|s| s.bytes as f64).sum::<f64>() / samples.len() as f64,
    })
}

/// Distances at which a recipient-relative cut is estimated.
pub const RELEVANCE_RADII_M: [f32; 3] = [16.0, 32.0, 64.0];

/// Snapshot composition seen by one reader, sampled about once a second.
#[derive(Debug, Clone, Default, Serialize, PartialEq)]
pub struct SnapshotShape {
    pub sampled: usize,
    pub mean_bytes: f64,
    pub mean_players: f64,
    /// Mean serialized bytes of each top-level Snapshot field, largest first.
    pub field_bytes: Vec<(String, f64)>,
    /// Mean serialized bytes of each field of one `players` entry, largest
    /// first: where a compact or delta encoding would have to save.
    pub player_field_bytes: Vec<(String, f64)>,
    /// For every live fighter as a recipient, the share of the other live
    /// fighters farther away than each radius in `RELEVANCE_RADII_M`.
    /// Straight-line distance only: no walls, sound or objectives.
    pub beyond_radius_share: Vec<(f32, f64)>,
    #[serde(skip)]
    totals: std::collections::BTreeMap<String, u64>,
    #[serde(skip)]
    player_totals: std::collections::BTreeMap<String, u64>,
    #[serde(skip)]
    bytes: u64,
    #[serde(skip)]
    players: u64,
    #[serde(skip)]
    pairs: u64,
    #[serde(skip)]
    beyond: [u64; 3],
}

impl SnapshotShape {
    /// Add one snapshot's text. Anything else is ignored.
    pub fn observe(&mut self, text: &str) {
        let Ok(serde_json::Value::Object(fields)) = serde_json::from_str(text) else {
            return;
        };
        if fields.get("type").and_then(serde_json::Value::as_str) != Some("snapshot") {
            return;
        }
        self.sampled += 1;
        self.bytes += text.len() as u64;
        for (key, value) in &fields {
            let size = serde_json::to_string(value).map_or(0, |text| text.len()) + key.len() + 4;
            *self.totals.entry(key.clone()).or_default() += size as u64;
        }
        for player in fields
            .get("players")
            .and_then(serde_json::Value::as_array)
            .into_iter()
            .flatten()
        {
            if let serde_json::Value::Object(entry) = player {
                for (key, value) in entry {
                    let size =
                        serde_json::to_string(value).map_or(0, |text| text.len()) + key.len() + 4;
                    *self.player_totals.entry(key.clone()).or_default() += size as u64;
                }
            }
        }
        let live: Vec<[f32; 3]> = fields
            .get("players")
            .and_then(serde_json::Value::as_array)
            .map(|players| {
                players
                    .iter()
                    .filter(|player| player["hp"].as_i64().unwrap_or(0) > 0)
                    .filter_map(|player| {
                        Some([
                            player["x"].as_f64()? as f32,
                            player["y"].as_f64().unwrap_or(0.0) as f32,
                            player["z"].as_f64()? as f32,
                        ])
                    })
                    .collect()
            })
            .unwrap_or_default();
        self.players += fields
            .get("players")
            .and_then(serde_json::Value::as_array)
            .map_or(0, |players| players.len() as u64);
        for (index, me) in live.iter().enumerate() {
            for (other_index, other) in live.iter().enumerate() {
                if index == other_index {
                    continue;
                }
                self.pairs += 1;
                let distance = ((me[0] - other[0]).powi(2)
                    + (me[1] - other[1]).powi(2)
                    + (me[2] - other[2]).powi(2))
                .sqrt();
                for (slot, radius) in RELEVANCE_RADII_M.iter().enumerate() {
                    self.beyond[slot] += u64::from(distance > *radius);
                }
            }
        }
    }

    /// Fill the reported means from the running totals.
    pub fn finish(&mut self) {
        if self.sampled == 0 {
            return;
        }
        let count = self.sampled as f64;
        self.mean_bytes = self.bytes as f64 / count;
        self.mean_players = self.players as f64 / count;
        let mut fields: Vec<(String, f64)> = self
            .totals
            .iter()
            .map(|(key, total)| (key.clone(), *total as f64 / count))
            .collect();
        fields.sort_by(|a, b| b.1.total_cmp(&a.1));
        self.field_bytes = fields;
        let entries = self.players.max(1) as f64;
        let mut player_fields: Vec<(String, f64)> = self
            .player_totals
            .iter()
            .map(|(key, total)| (key.clone(), *total as f64 / entries))
            .collect();
        player_fields.sort_by(|a, b| b.1.total_cmp(&a.1));
        self.player_field_bytes = player_fields;
        self.beyond_radius_share = RELEVANCE_RADII_M
            .iter()
            .zip(self.beyond)
            .map(|(radius, beyond)| {
                let share = if self.pairs == 0 {
                    0.0
                } else {
                    beyond as f64 / self.pairs as f64
                };
                (*radius, share)
            })
            .collect();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn schedstat_and_skmem_parse() {
        assert_eq!(parse_schedstat("1125641 0 4\n"), Some(1_125_641));
        assert_eq!(parse_schedstat(""), None);
        let text = "0 0 127.0.0.1:6767 127.0.0.1:5000\n\t skmem:(r0,rb131072,t4096,tb2626560,f1024,w2048,o0,bl0,d0)\n\
                    0 0 127.0.0.1:6767 127.0.0.1:5001\n\t skmem:(r512,rb131072,t0,tb87040,f0,w0,o0,bl0,d1)\n";
        let memory = parse_skmem(text);
        assert_eq!(memory.sockets, 2);
        assert_eq!(memory.rmem_alloc, 512);
        assert_eq!(memory.wmem_alloc, 4096);
        assert_eq!(memory.wmem_queued, 2048);
        assert_eq!(memory.fwd_alloc, 1024);
        assert_eq!(memory.max_send_bytes, 6144);
        assert_eq!(memory.total(), 512 + 4096 + 2048 + 1024);
        assert_eq!(parse_skmem("no sockets"), SocketMemory::default());
    }

    #[test]
    fn a_tick_window_keeps_the_held_ticks() {
        let dir = std::env::temp_dir().join(format!("fragr-tick-window-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("ticks.ndjson");
        let tick = |tick: u64, total_us: u64, skipped: u64| {
            serde_json::to_string(&TickTraceRecord::Tick(
                fragr_server::tick_trace::TickSample {
                    tick,
                    unix_us: 0,
                    late_us: 1000 * tick,
                    skipped,
                    sim_us: 100,
                    measure_us: 20,
                    fanout_us: 30,
                    total_us,
                    clients: 3,
                    messages: 2,
                    bytes: 1000,
                    overflows: 0,
                },
            ))
            .unwrap()
        };
        let text = [
            tick(1, 60_000, 0),
            tick(2, 1_000, 2),
            tick(3, 52_000, 0),
            tick(4, 2_000, 0),
            "{\"record\":\"tick\",\"tick\":5,".to_string(),
        ]
        .join("\n");
        std::fs::write(&path, text).unwrap();
        let window = tick_window(&path, 2, 4).unwrap();
        assert_eq!(window.ticks, 3);
        assert_eq!(window.over_budget, 1);
        assert_eq!(window.skipped_periods, 2);
        assert_eq!(window.late_ms.max, 4.0);
        assert_eq!(window.total_ms.max, 52.0);
        assert_eq!(window.bytes_per_tick, 1000.0);
        assert!(tick_window(&path, 10, 20).is_err());
        assert!(tick_window(&dir.join("missing"), 1, 2).is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn snapshot_shape_counts_fields_and_distances() {
        let mut shape = SnapshotShape::default();
        shape.observe(r#"{"type":"ack","seq":1}"#);
        shape.observe("not json");
        shape.observe(
            r#"{"type":"snapshot","tick":1,"players":[
                {"x":0,"y":0,"z":0,"hp":100},
                {"x":20,"y":0,"z":0,"hp":100},
                {"x":100,"y":0,"z":0,"hp":100},
                {"x":5,"y":0,"z":0,"hp":0}
            ]}"#,
        );
        shape.finish();
        assert_eq!(shape.sampled, 1);
        assert_eq!(shape.mean_players, 4.0);
        assert_eq!(shape.field_bytes[0].0, "players");
        // Four entries, each with x, y, z and hp.
        assert_eq!(shape.player_field_bytes.len(), 4);
        let hp = shape
            .player_field_bytes
            .iter()
            .find(|(key, _)| key == "hp")
            .unwrap();
        assert!((hp.1 - 8.5).abs() < 1e-9, "{hp:?}");
        // Six ordered pairs among three live fighters: 20, 100 and 80 apart.
        let shares: Vec<f64> = shape.beyond_radius_share.iter().map(|(_, s)| *s).collect();
        assert_eq!(shares, vec![1.0, 4.0 / 6.0, 4.0 / 6.0]);
        let mut empty = SnapshotShape::default();
        empty.finish();
        assert_eq!(empty.mean_bytes, 0.0);
    }

    #[test]
    fn this_process_has_cpu_time_on_linux() {
        if cfg!(target_os = "linux") {
            assert!(cpu_ns(std::process::id()).is_some());
        }
        assert!(cpu_ns(u32::MAX).is_none());
        assert_eq!(
            Spread::of(&mut [3.0, 1.0, 2.0]),
            Spread {
                samples: 3,
                p50: 2.0,
                p99: 3.0,
                max: 3.0
            }
        );
    }
}
