use super::*;

fn status(tick: u64, p99_ms: f64, out_bytes: u64, overflows: u64, degraded: bool) -> LiveStatus {
    let health = if degraded {
        r#"{"status":"degraded","reasons":["tick_p99_over_budget"]}"#
    } else {
        r#"{"status":"ok","reasons":[]}"#
    };
    let tick_summary = format!(
        r#"{{"count":1200,"p50_ms":1.0,"p95_ms":2.0,"p99_ms":{p99_ms},"max_ms":{p99_ms},"over_budget":0}}"#
    );
    serde_json::from_str(&format!(
        r#"{{"schema_version":2,"kind":"arena","map":"Arena Duel","round":1,"tick":{tick},
        "fighters":8,"humans":0,"agents":2,"bots":4,"connections":3,
        "health":{health},
        "ops":{{"version":1,
          "build":{{"crate_version":"0.1.0","release":null,"commit":"abcdef1"}},
          "process":{{"started_unix_s":1,"uptime_s":2.0}},
          "tick":{{"budget_ms":50.0,"scope":"tick_handler","window_s":60,
            "window":{tick_summary},"lifetime":{tick_summary}}},
          "connections":{{"total":3,"spectators":1,"humans":0,"agents":2}},
          "traffic":{{"window_s":60,"out_bytes_per_s":1.0,"in_bytes_per_s":1.0,
            "out_msgs_per_s":1.0,"in_msgs_per_s":1.0,
            "per_client_out_bytes_per_s_mean":1.0,"per_client_out_bytes_per_s_max":1.0,
            "out_bytes":{out_bytes},"in_bytes":{},"out_msgs":1,"in_msgs":1,
            "queue_overflows_window":0,"queue_overflows_total":{overflows}}}}}}}"#,
        out_bytes / 10
    ))
    .unwrap()
}

fn sample(index: usize, elapsed_s: f64, status: Option<LiveStatus>, rss: Option<u64>) -> Sample {
    Sample {
        kind: "sample",
        index,
        elapsed_s,
        unix_ms: 0,
        server_alive: true,
        rss: rss.map(|bytes| Rss {
            bytes,
            source: "test",
        }),
        rss_unavailable: rss.is_none().then(|| "test".to_string()),
        agents_live: 2,
        spectators_live: 1,
        status,
        status_error: None,
    }
}

const EXPECTED: Expected = Expected {
    agents: 2,
    spectators: 1,
};

const MIB: u64 = 1024 * 1024;

fn healthy() -> Vec<Sample> {
    vec![
        sample(0, 0.0, Some(status(100, 3.0, 0, 0, false)), Some(40 * MIB)),
        sample(
            1,
            60.0,
            Some(status(1300, 3.5, 300_000, 0, false)),
            Some(42 * MIB),
        ),
        sample(
            2,
            120.0,
            Some(status(2500, 4.0, 600_000, 0, false)),
            Some(41 * MIB),
        ),
    ]
}

#[test]
fn a_clean_soak_passes_and_summarizes_the_table() {
    let verdict = check_soak(&healthy(), EXPECTED);
    assert!(verdict.passed, "{:?}", verdict.problems);
    assert!(verdict.notes.is_empty());
    let summary = verdict.summary;
    assert_eq!(summary.samples, 3);
    assert_eq!(summary.measured_s, 120.0);
    assert_eq!((summary.ticks_start, summary.ticks_end), (100, 2500));
    assert_eq!(summary.window_start.p99_ms, 3.0);
    assert_eq!(summary.window_end.p99_ms, 4.0);
    assert_eq!(summary.lifetime_end.p95_ms, 2.0);
    // 600000 bytes over 120 s across three clients.
    assert!((summary.out_bytes_per_client_per_s - 600_000.0 / 120.0 / 3.0).abs() < 1e-9);
    assert!((summary.in_bytes_per_client_per_s - 60_000.0 / 120.0 / 3.0).abs() < 1e-9);
    assert_eq!(summary.rss_start, Some(40 * MIB));
    assert_eq!(summary.rss_end, Some(41 * MIB));
    assert_eq!(summary.rss_max, Some(42 * MIB));
    assert_eq!(summary.rss_source, Some("test"));
    assert_eq!(summary.build_commit.as_deref(), Some("abcdef1"));
    let json = serde_json::to_value(verdict_line(&healthy())).unwrap();
    assert_eq!(json["kind"], "verdict");
    assert_eq!(json["schema"], SOAK_SCHEMA);
}

fn verdict_line(samples: &[Sample]) -> Verdict {
    check_soak(samples, EXPECTED)
}

fn problems(samples: &[Sample]) -> Vec<String> {
    let verdict = check_soak(samples, EXPECTED);
    assert!(!verdict.passed);
    verdict.problems
}

#[test]
fn a_crash_a_stall_or_a_missing_status_fails() {
    let mut crashed = healthy();
    crashed[2].server_alive = false;
    assert!(problems(&crashed)[0].contains("server process had exited"));

    let mut stalled = healthy();
    stalled[2].status = Some(status(1300, 4.0, 600_000, 0, false));
    assert!(problems(&stalled)[0].contains("did not advance"));

    let mut silent = healthy();
    silent[1].status = None;
    silent[1].status_error = Some("timed out".into());
    assert!(problems(&silent)[0].contains("no status (timed out)"));

    let mut bare = healthy();
    bare[1].status.as_mut().unwrap().ops = None;
    assert!(problems(&bare)[0].contains("no operator block"));

    assert!(problems(&healthy()[..1])[0].contains("needs a start and an end"));
}

#[test]
fn connection_drift_fails_on_either_side() {
    let mut dropped = healthy();
    dropped[1].agents_live = 1;
    assert!(problems(&dropped)[0].contains("1 of 2 agents"));

    let mut counted = healthy();
    counted[2].status.as_mut().unwrap().connections = 2;
    assert!(problems(&counted)[0].contains("2 connections, expected 3"));

    let mut roles = healthy();
    roles[2]
        .status
        .as_mut()
        .unwrap()
        .ops
        .as_mut()
        .unwrap()
        .connections
        .spectators = 0;
    assert!(problems(&roles)[0].contains("2 agents and 0 spectators"));
}

#[test]
fn slow_ticks_degraded_health_and_queue_drops_fail() {
    let mut slow = healthy();
    slow[2].status = Some(status(2500, 50.0, 600_000, 0, false));
    assert!(problems(&slow)[0].contains("lifetime p99 tick 50.00 ms"));

    let mut degraded = healthy();
    degraded[1].status = Some(status(1300, 3.0, 300_000, 0, true));
    let verdict = check_soak(&degraded, EXPECTED);
    assert_eq!(verdict.summary.degraded_samples, 1);
    assert!(verdict.problems[0].contains("health degraded"));

    let mut dropped = healthy();
    dropped[2].status = Some(status(2500, 4.0, 600_000, 2, false));
    assert!(problems(&dropped)[0].contains("2 outbound queue overflows"));
}

#[test]
fn memory_growth_is_bounded_and_missing_memory_is_a_note() {
    let mut grew = healthy();
    grew[2].rss = Some(Rss {
        bytes: 40 * MIB + 65 * MIB,
        source: "test",
    });
    assert!(problems(&grew)[0].contains("grew 65 MiB, more than the 64 MiB allowed"));

    // A large process may grow by half before failing.
    let mut large = healthy();
    for (sample, mib) in large.iter_mut().zip([400, 500, 590]) {
        sample.rss = Some(Rss {
            bytes: mib * MIB,
            source: "test",
        });
    }
    assert!(check_soak(&large, EXPECTED).passed);
    large[2].rss.as_mut().unwrap().bytes = 601 * MIB;
    assert!(problems(&large)[0].contains("more than the 200 MiB allowed"));

    let mut unknown = healthy();
    unknown[1].rss = None;
    let verdict = check_soak(&unknown, EXPECTED);
    assert!(verdict.passed);
    assert_eq!(verdict.summary.rss_start, None);
    assert!(verdict.notes[0].contains("unavailable for 1 of 3 samples"));
}

#[test]
fn os_memory_reports_parse_and_reject_garbage() {
    assert_eq!(
        parse_proc_status("Name:\tfragr-server\nVmPeak:\t 99 kB\nVmRSS:\t   12345 kB\n"),
        Some(12345 * 1024)
    );
    assert_eq!(parse_proc_status("VmRSS: lots"), None);
    assert_eq!(parse_proc_status(""), None);
    assert_eq!(parse_ps_rss("  2048\n"), Some(2048 * 1024));
    assert_eq!(parse_ps_rss(""), None);
    let csv = "\"fragr-server.exe\",\"4242\",\"Console\",\"1\",\"45,678 K\"\r\n";
    assert_eq!(parse_tasklist_csv(csv, 4242), Some(45_678 * 1024));
    let dotted = "\"fragr-server.exe\",\"77\",\"Services\",\"0\",\"1.234.567 K\"";
    assert_eq!(parse_tasklist_csv(dotted, 77), Some(1_234_567 * 1024));
    assert_eq!(parse_tasklist_csv(csv, 99), None);
    assert_eq!(
        parse_tasklist_csv(
            "INFO: No tasks are running which match the specified criteria.",
            4242
        ),
        None
    );
    // This process is always there to measure, on every supported OS.
    match sample_rss(std::process::id()) {
        Ok(rss) => assert!(rss.bytes > 1024 * 1024, "{rss:?}"),
        Err(reason) => assert!(!reason.is_empty()),
    }
}

#[test]
fn configuration_is_validated_before_anything_starts() {
    let base = SoakConfig {
        seconds: 60,
        sample_seconds: 10,
        bots: 4,
        agents: 4,
        spectators: 2,
        map: MapKind::ArenaDuel,
        map_rotate: false,
        seed: 1,
        launch: Launch::InProcess,
        log: PathBuf::from(".agents/soak/test.ndjson"),
    };
    assert!(base.validate().is_ok());
    for broken in [
        SoakConfig {
            seconds: 0,
            ..base.clone()
        },
        SoakConfig {
            sample_seconds: 0,
            ..base.clone()
        },
        SoakConfig {
            sample_seconds: 61,
            ..base.clone()
        },
        SoakConfig {
            agents: 0,
            spectators: 0,
            ..base.clone()
        },
        SoakConfig {
            agents: 30,
            spectators: 2,
            ..base.clone()
        },
    ] {
        assert!(broken.validate().is_err(), "{broken:?}");
    }
    let _ = default_server_binary();
}

#[tokio::test]
async fn status_fetch_reports_a_closed_port() {
    let port = free_loopback_port().unwrap();
    let error = fetch_status(([127, 0, 0, 1], port).into(), "/status")
        .await
        .unwrap_err();
    assert!(matches!(error, Error::Io(_) | Error::Timeout(_)), "{error}");
}

#[tokio::test]
async fn a_missing_binary_is_a_start_error() {
    let dir = std::env::temp_dir().join(format!("fragr-soak-missing-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let error = run_soak(SoakConfig {
        seconds: 2,
        sample_seconds: 1,
        bots: 0,
        agents: 1,
        spectators: 0,
        map: MapKind::ArenaDuel,
        map_rotate: false,
        seed: 1,
        launch: Launch::Binary(dir.join("no-such-fragr-server")),
        log: dir.join("missing.ndjson"),
    })
    .await
    .unwrap_err();
    assert!(error.to_string().contains("cannot start"), "{error}");
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn a_short_in_process_soak_samples_and_passes() {
    let dir = std::env::temp_dir().join(format!("fragr-soak-test-{}", std::process::id()));
    let log = dir.join("soak.ndjson");
    let verdict = run_soak(SoakConfig {
        seconds: 3,
        sample_seconds: 1,
        bots: 2,
        agents: 2,
        spectators: 1,
        map: MapKind::ArenaDuel,
        map_rotate: false,
        seed: 7,
        launch: Launch::InProcess,
        log: log.clone(),
    })
    .await
    .unwrap();
    // Unoptimized coverage builds can be slow per tick; the shape is what matters.
    let structural: Vec<&String> = verdict
        .problems
        .iter()
        .filter(|problem| !problem.contains("p99") && !problem.contains("degraded"))
        .collect();
    assert!(structural.is_empty(), "{:?}", verdict.problems);
    assert!(verdict.summary.samples >= 4, "{:?}", verdict.summary);
    assert!(verdict.summary.ticks_end > verdict.summary.ticks_start);
    assert!(verdict.summary.out_bytes_per_client_per_s > 0.0);
    let text = std::fs::read_to_string(&log).unwrap();
    let lines: Vec<serde_json::Value> = text
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(lines.first().unwrap()["kind"], "start");
    assert_eq!(lines.first().unwrap()["launch"], "in_process");
    assert_eq!(lines.last().unwrap()["kind"], "verdict");
    let samples: Vec<&serde_json::Value> = lines
        .iter()
        .filter(|line| line["kind"] == "sample")
        .collect();
    assert_eq!(samples.len(), verdict.summary.samples);
    let first = &samples[0]["status"];
    assert_eq!(first["schema_version"], 2);
    assert_eq!(first["ops"]["connections"]["agents"], 2);
    assert_eq!(first["ops"]["clients"].as_array().unwrap().len(), 3);
    let _ = std::fs::remove_dir_all(dir);
}
