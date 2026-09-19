//! Streaming offline recordings. Hash the exact NDJSON header, tick, and score records,
//! including their LF terminators. A footer proves completion but is not hashed.

use crate::bench::BenchConfig;
use crate::protocol::ServerMessage;
use crate::session::Recipient;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::io::{self, BufRead, Read, Write};

pub const TRACE_VERSION: u32 = 1;
const MAX_RECORD_BYTES: u64 = 8 * 1024 * 1024;

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "record", rename_all = "snake_case", deny_unknown_fields)]
pub enum TraceRecord {
    Header {
        version: u32,
        tick_hz: u32,
        config: BenchConfig,
    },
    Tick {
        tick: u64,
        broadcast: Vec<ServerMessage>,
        unicasts: Vec<(Recipient, ServerMessage)>,
    },
    Scores {
        frags: Vec<(String, u32)>,
    },
    Complete {
        ticks: u64,
        sha256: String,
    },
}

/// A sink is optional: every benchmark hashes the same recording, whether or
/// not the caller exports it. Hashing and disk IO stay outside CPU phase timing.
pub(crate) struct Recorder<'a> {
    sink: Option<&'a mut dyn Write>,
    hash: Sha256,
    buffer: Vec<u8>,
}

impl<'a> Recorder<'a> {
    pub fn new(sink: Option<&'a mut dyn Write>) -> Self {
        Self {
            sink,
            hash: Sha256::new(),
            buffer: Vec::new(),
        }
    }

    pub fn record(&mut self, record: &TraceRecord) -> io::Result<()> {
        self.buffer.clear();
        serde_json::to_writer(&mut self.buffer, record)?;
        self.buffer.push(b'\n');
        self.hash.update(&self.buffer);
        if let Some(sink) = self.sink.as_mut() {
            sink.write_all(&self.buffer)?;
        }
        Ok(())
    }

    pub fn finish(mut self, ticks: u64, frags: Vec<(String, u32)>) -> io::Result<String> {
        self.record(&TraceRecord::Scores { frags })?;
        let sha256 = hex_digest(self.hash.finalize().as_slice());
        if let Some(sink) = self.sink.as_mut() {
            serde_json::to_writer(
                &mut **sink,
                &TraceRecord::Complete {
                    ticks,
                    sha256: sha256.clone(),
                },
            )?;
            sink.write_all(b"\n")?;
            sink.flush()?;
        }
        Ok(sha256)
    }
}

fn hex_digest(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

#[derive(Debug, Serialize)]
pub struct TraceSummary {
    pub config: BenchConfig,
    pub ticks: u64,
    pub sha256: String,
    pub frags: Vec<(String, u32)>,
}

/// Verify framing, schema, record order, contiguous ticks, snapshot tick numbers,
/// and content integrity before accepting an offline artifact. Memory is bounded
/// by one record. A valid hash establishes integrity, not trusted authorship.
pub fn verify_trace(mut reader: impl BufRead) -> io::Result<TraceSummary> {
    let mut line = Vec::new();
    let mut hash = Sha256::new();
    let mut config: Option<BenchConfig> = None;
    let mut frags = None;
    let mut ticks = 0;
    let mut completed = None;
    loop {
        line.clear();
        // read_until alone can allocate the size of an untrusted file with no LF.
        let read = (&mut reader)
            .take(MAX_RECORD_BYTES + 1)
            .read_until(b'\n', &mut line)?;
        if read == 0 {
            break;
        }
        if read as u64 > MAX_RECORD_BYTES || line.last() != Some(&b'\n') {
            return Err(invalid("trace record is too large or has no LF terminator"));
        }
        if completed.is_some() {
            return Err(invalid("data after trace completion"));
        }
        let record: TraceRecord = serde_json::from_slice(&line)?;
        match record {
            TraceRecord::Header {
                version,
                tick_hz,
                config: header,
            } => {
                if config.is_some()
                    || version != TRACE_VERSION
                    || tick_hz != 20
                    || header.ticks == 0
                {
                    return Err(invalid("invalid or duplicate trace header"));
                }
                config = Some(header);
            }
            TraceRecord::Tick {
                tick, broadcast, ..
            } => {
                let header = config
                    .as_ref()
                    .ok_or_else(|| invalid("tick before header"))?;
                if frags.is_some() || tick != ticks + 1 || tick > header.ticks {
                    return Err(invalid("trace ticks are out of order or exceed the header"));
                }
                let snapshots: Vec<_> = broadcast
                    .iter()
                    .filter_map(|message| match message {
                        ServerMessage::Snapshot(snapshot) => Some(snapshot),
                        _ => None,
                    })
                    .collect();
                if snapshots.len() != 1 || snapshots[0].tick != tick {
                    return Err(invalid("each trace tick needs one matching snapshot"));
                }
                ticks = tick;
            }
            TraceRecord::Scores { frags: scores } => {
                if config.as_ref().map(|c| c.ticks) != Some(ticks) || frags.is_some() {
                    return Err(invalid("scores before all ticks or duplicate scores"));
                }
                frags = Some(scores);
            }
            TraceRecord::Complete {
                ticks: total,
                sha256,
            } => {
                if total != ticks || frags.is_none() {
                    return Err(invalid("trace completion count or scores are missing"));
                }
                if sha256 != hex_digest(hash.clone().finalize().as_slice()) {
                    return Err(invalid("trace SHA-256 does not match its content"));
                }
                completed = Some(sha256);
                continue;
            }
        }
        hash.update(&line);
    }
    Ok(TraceSummary {
        config: config.ok_or_else(|| invalid("trace header is missing"))?,
        ticks,
        sha256: completed.ok_or_else(|| invalid("trace is incomplete"))?,
        frags: frags.ok_or_else(|| invalid("trace scores are missing"))?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bench::{check_repeated, run_bench_with_trace};
    use crate::protocol::GameEvent;
    use crate::sim::MapKind;

    fn recorded(ticks: u64) -> (crate::bench::BenchReport, Vec<u8>) {
        let mut bytes = Vec::new();
        let report =
            run_bench_with_trace(4, ticks, MapKind::ArenaDuel, 42, Some(&mut bytes)).unwrap();
        (report, bytes)
    }

    #[test]
    fn trace_repeats_through_drone_and_round_transitions() {
        let (report, bytes) = recorded(4000);
        let verified = verify_trace(&bytes[..]).unwrap();
        assert_eq!(verified.sha256, report.trace_sha256);
        assert_eq!(verified.frags, report.frags);
        assert_eq!(verified.config, report.config);
        assert_eq!(verified.ticks, 4000);
        let mut saw_drone = false;
        let mut saw_round_end = false;
        let mut payload_bytes = 0;
        for line in bytes.split_inclusive(|b| *b == b'\n') {
            if let TraceRecord::Tick { broadcast, .. } = serde_json::from_slice(line).unwrap() {
                for message in &broadcast {
                    payload_bytes += serde_json::to_vec(message).unwrap().len();
                    saw_drone |=
                        matches!(message, ServerMessage::Event(GameEvent::BossSpawn { .. }));
                    saw_round_end |=
                        matches!(message, ServerMessage::Event(GameEvent::RoundEnd { .. }));
                }
            }
        }
        assert!(
            saw_drone && saw_round_end,
            "recording must exercise dynamic identity and podium ordering"
        );
        assert!((report.stats.broadcast_bytes.mean * 4000.0 - payload_bytes as f64).abs() < 0.01);
        assert_eq!(check_repeated(report).unwrap().deterministic, Some(true));
    }

    #[test]
    fn changed_intermediate_position_and_scores_fail_integrity() {
        let (report, bytes) = recorded(20);
        let mut lines: Vec<String> = String::from_utf8(bytes)
            .unwrap()
            .lines()
            .map(str::to_string)
            .collect();
        let original = lines[5].clone();
        let mut tick: TraceRecord = serde_json::from_str(&lines[5]).unwrap();
        if let TraceRecord::Tick { broadcast, .. } = &mut tick {
            for message in broadcast {
                if let ServerMessage::Snapshot(snapshot) = message {
                    snapshot.players[0].x += 1.0;
                }
            }
        }
        lines[5] = serde_json::to_string(&tick).unwrap();
        let changed = lines.join("\n") + "\n";
        assert!(verify_trace(changed.as_bytes())
            .unwrap_err()
            .to_string()
            .contains("SHA-256"));
        let footer: TraceRecord = serde_json::from_str(lines.last().unwrap()).unwrap();
        assert!(
            matches!(footer, TraceRecord::Complete { sha256, .. } if sha256 == report.trace_sha256)
        );
        lines[5] = original;
        let score_index = lines.len() - 2;
        lines[score_index] = serde_json::to_string(&TraceRecord::Scores {
            frags: vec![("Forged".into(), 999)],
        })
        .unwrap();
        assert!(verify_trace((lines.join("\n") + "\n").as_bytes()).is_err());
    }

    #[test]
    fn incomplete_reordered_unsupported_and_oversized_traces_are_rejected() {
        let (_, bytes) = recorded(3);
        let lines: Vec<_> = bytes
            .split_inclusive(|b| *b == b'\n')
            .map(<[u8]>::to_vec)
            .collect();
        let rejects = |records: Vec<Vec<u8>>| assert!(verify_trace(&records.concat()[..]).is_err());
        rejects(vec![]);
        rejects(lines[..lines.len() - 1].to_vec());
        rejects(lines[1..].to_vec());
        let mut copy = lines.clone();
        copy.swap(1, 2);
        rejects(copy);
        let mut copy = lines.clone();
        copy.insert(1, lines[0].clone());
        rejects(copy);
        let mut copy = lines.clone();
        copy.push(lines[0].clone());
        rejects(copy);
        let mut copy = lines.clone();
        copy.swap(2, lines.len() - 2);
        rejects(copy);
        let mut copy = lines.clone();
        copy.insert(lines.len() - 1, lines[lines.len() - 2].clone());
        rejects(copy);
        let mut copy = lines.clone();
        copy[0] = b"{\"record\":\"header\",\"version\":999}\n".to_vec();
        rejects(copy);
        let mut copy = bytes.clone();
        copy.pop();
        assert!(verify_trace(&copy[..]).is_err());
        assert!(verify_trace(&vec![b' '; MAX_RECORD_BYTES as usize + 1][..]).is_err());
    }

    #[test]
    fn wrong_snapshot_tick_and_completion_count_are_rejected() {
        let (_, bytes) = recorded(2);
        let mut lines: Vec<_> = bytes
            .split_inclusive(|b| *b == b'\n')
            .map(<[u8]>::to_vec)
            .collect();
        let mut record: TraceRecord = serde_json::from_slice(&lines[1]).unwrap();
        if let TraceRecord::Tick { broadcast, .. } = &mut record {
            for message in broadcast {
                if let ServerMessage::Snapshot(snapshot) = message {
                    snapshot.tick = 99;
                }
            }
        }
        lines[1] = serde_json::to_vec(&record).unwrap();
        lines[1].push(b'\n');
        assert!(verify_trace(&lines.concat()[..])
            .unwrap_err()
            .to_string()
            .contains("matching snapshot"));
        let mut lines: Vec<_> = bytes
            .split_inclusive(|b| *b == b'\n')
            .map(<[u8]>::to_vec)
            .collect();
        *lines.last_mut().unwrap() =
            b"{\"record\":\"complete\",\"ticks\":3,\"sha256\":\"bad\"}\n".to_vec();
        assert!(verify_trace(&lines.concat()[..])
            .unwrap_err()
            .to_string()
            .contains("completion count"));
    }

    #[test]
    fn header_versions_and_targeted_payloads_are_part_of_the_contract() {
        let (report, bytes) = recorded(2);
        let lines: Vec<_> = bytes.split_inclusive(|b| *b == b'\n').collect();
        for (field, value) in [("version", 999), ("tick_hz", 0)] {
            let mut header: serde_json::Value = serde_json::from_slice(lines[0]).unwrap();
            header[field] = value.into();
            let mut altered = serde_json::to_vec(&header).unwrap();
            altered.push(b'\n');
            altered.extend_from_slice(&lines[1..].concat());
            assert!(verify_trace(&altered[..])
                .unwrap_err()
                .to_string()
                .contains("header"));
        }
        let mut changed = Vec::new();
        let mut recorder = Recorder::new(Some(&mut changed));
        for (index, line) in lines[..3].iter().enumerate() {
            let mut record: TraceRecord = serde_json::from_slice(line).unwrap();
            if let TraceRecord::Tick { unicasts, tick, .. } = &mut record {
                let ack = ServerMessage::Ack {
                    seq: index as u32,
                    tick: *tick,
                    x: 1.0,
                    z: 2.0,
                    yaw: 0.0,
                };
                assert_eq!(
                    crate::bench::encoded_payload_bytes(std::iter::once(&ack)).unwrap(),
                    serde_json::to_vec(&ack).unwrap().len()
                );
                unicasts.push((Recipient::Player(uuid::Uuid::from_u128(1)), ack));
            }
            recorder.record(&record).unwrap();
        }
        let hash = recorder.finish(2, report.frags).unwrap();
        assert_ne!(hash, report.trace_sha256);
        assert_eq!(verify_trace(&changed[..]).unwrap().sha256, hash);
    }

    struct BrokenWriter {
        fail_flush: bool,
    }
    impl Write for BrokenWriter {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            if self.fail_flush {
                Ok(bytes.len())
            } else {
                Err(io::Error::other("disk full"))
            }
        }
        fn flush(&mut self) -> io::Result<()> {
            Err(io::Error::other("flush failed"))
        }
    }

    #[test]
    fn failed_writes_and_flushes_never_report_success() {
        for fail_flush in [false, true] {
            let mut writer = BrokenWriter { fail_flush };
            let error =
                run_bench_with_trace(1, 2, MapKind::ArenaDuel, 1, Some(&mut writer)).unwrap_err();
            assert!(error.to_string().contains(if fail_flush {
                "flush failed"
            } else {
                "disk full"
            }));
        }
    }
}
