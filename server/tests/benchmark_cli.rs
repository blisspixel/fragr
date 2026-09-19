use std::process::{Command, Output};

fn run(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_fragr-server"))
        .args(args)
        .output()
        .expect("start benchmark CLI")
}

#[test]
fn trace_cli_round_trip_refuses_overwrite_and_corruption() {
    let path = std::env::temp_dir().join(format!("fragr-bench-{}.ndjson", uuid::Uuid::new_v4()));
    let path_text = path.to_str().unwrap();
    let recorded = run(&[
        "--bench",
        "4",
        "--bench-ticks",
        "20",
        "--bench-check",
        "--bench-trace",
        path_text,
    ]);
    assert!(
        recorded.status.success(),
        "{}",
        String::from_utf8_lossy(&recorded.stderr)
    );
    let report: serde_json::Value = serde_json::from_slice(&recorded.stdout).unwrap();
    assert_eq!(report["deterministic"], true);
    let original = std::fs::read(&path).unwrap();
    let verified = run(&["--bench-verify-trace", path_text]);
    assert!(verified.status.success());
    let summary: serde_json::Value = serde_json::from_slice(&verified.stdout).unwrap();
    assert_eq!(summary["sha256"], report["trace_sha256"]);
    let duplicate = run(&["--bench", "1", "--bench-trace", path_text]);
    assert!(!duplicate.status.success());
    assert!(duplicate.stdout.is_empty());
    assert_eq!(std::fs::read(&path).unwrap(), original);
    std::fs::write(&path, b"incomplete\n").unwrap();
    assert!(!run(&["--bench-verify-trace", path_text]).status.success());
    std::fs::remove_file(&path).unwrap();
    assert!(!run(&["--bench-verify-trace", path_text]).status.success());
}

#[test]
fn impossible_budget_returns_report_and_failure_status() {
    let output = run(&[
        "--bench",
        "4",
        "--bench-ticks",
        "10",
        "--bench-assert",
        "--bench-max-budget-p99",
        "0.000000001",
    ]);
    assert!(!output.status.success());
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["stats"]["ticks"], 10);
    assert!(String::from_utf8_lossy(&output.stderr).contains("over the"));
}
