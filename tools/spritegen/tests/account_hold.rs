use std::path::PathBuf;
use std::process::Command;

struct Scratch(PathBuf);
impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[test]
fn absolute_credentials_keep_account_hold_when_cli_runs_elsewhere() {
    let root = Scratch(std::env::temp_dir().join(format!(
        "fragr-model-carry-cli-{}-{}", std::process::id(),
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()
    )));
    let account = root.0.join("account");
    let elsewhere = root.0.join("elsewhere");
    std::fs::create_dir_all(&account).unwrap();
    std::fs::create_dir_all(&elsewhere).unwrap();
    let credential = account.join(".env");
    std::fs::write(&credential, "meshy=test-only-no-network-key\n").unwrap();
    let invoke = |args: &[&str]| {
        Command::new(env!("CARGO_BIN_EXE_fragr-spritegen"))
            .current_dir(&elsewhere)
            .arg("--env-file")
            .arg(&credential)
            .args(args)
            .output()
            .unwrap()
    };
    let retained = invoke(&[
        "meshy-hold",
        "--credits",
        "15",
        "--reason",
        "historical uncertainty",
    ]);
    assert!(
        retained.status.success(),
        "{}",
        String::from_utf8_lossy(&retained.stderr)
    );
    let hold = account.join("art/raw/meshy-account-hold.json");
    assert!(hold.is_file());
    assert!(!elsewhere.join("art/raw/meshy-account-hold.json").exists());
    assert!(
        !invoke(&["meshy-hold", "--credits", "1", "--reason", "replace"])
            .status
            .success()
    );

    // Both entry points must see the account's malformed hold before HTTP.
    std::fs::write(&hold, "broken hold").unwrap();
    let checked = invoke(&["meshy-check"]);
    assert!(!checked.status.success());
    assert!(
        String::from_utf8_lossy(&checked.stderr).contains("invalid external model hold document")
    );
    let spec = account.join("model.json");
    std::fs::write(
        &spec,
        serde_json::json!({"out_dir": elsewhere.join("fresh-output"),
        "jobs":[{"id":"fresh","kind":"rig","input_task_id":"task-a","height_meters":1.8}]})
        .to_string(),
    )
    .unwrap();
    let generated = invoke(&[
        "meshy-gen",
        "--spec",
        spec.to_str().unwrap(),
        "--max-credits",
        "5",
        "--max-spend-usd",
        "0.10",
    ]);
    assert!(!generated.status.success());
    assert!(
        String::from_utf8_lossy(&generated.stderr).contains("invalid external model hold document")
    );
    assert!(!elsewhere.join("fresh-output/ledger.jsonl").exists());
}
