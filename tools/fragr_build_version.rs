// Shared build script. Each binary crate includes this so `--version`,
// `/status` `build.release`, and the MCP `serverInfo.version` are one string:
// `FRAGR_BUILD_VERSION` when a release build sets it, otherwise
// `git describe --tags --always`.

use std::process::Command;

fn main() {
    let commit = nonempty("FRAGR_BUILD_COMMIT").or_else(|| git(&["rev-parse", "HEAD"]));
    let release = nonempty("FRAGR_BUILD_VERSION")
        .and_then(|value| release_token(&value))
        .or_else(|| {
            git(&[
                "describe",
                "--tags",
                "--always",
                "--abbrev=12",
            ])
            .and_then(|value| release_token(&value))
        });
    let cli = release
        .clone()
        .unwrap_or_else(|| std::env::var("CARGO_PKG_VERSION").unwrap_or_else(|_| "0.1.0".into()));
    if let Some(commit) = commit.filter(|value| commit_token(value)) {
        println!("cargo:rustc-env=FRAGR_BUILD_COMMIT={commit}");
    }
    println!("cargo:rustc-env=FRAGR_BUILD_VERSION={cli}");
    println!("cargo:rustc-env=FRAGR_CLI_VERSION={cli}");
    println!("cargo:rerun-if-env-changed=FRAGR_BUILD_COMMIT");
    println!("cargo:rerun-if-env-changed=FRAGR_BUILD_VERSION");
    if let Some(head) = git(&["rev-parse", "--absolute-git-dir"]) {
        println!("cargo:rerun-if-changed={head}/HEAD");
    }
}

fn nonempty(key: &str) -> Option<String> {
    std::env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn git(args: &[&str]) -> Option<String> {
    let dir = std::env::var("CARGO_MANIFEST_DIR").ok()?;
    let output = Command::new("git").args(args).current_dir(dir).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8(output.stdout).ok()?;
    let text = text.trim();
    if text.is_empty() || text.contains('\n') || text.contains('\r') {
        return None;
    }
    Some(text.to_string())
}

/// Same alphabet `/status` keeps for `build.release`, so the CLI string is not
/// stripped when the server records it.
fn release_token(value: &str) -> Option<String> {
    let value = value.trim();
    ((1..=64).contains(&value.len())
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | '+')))
    .then(|| value.to_string())
}

fn commit_token(value: &str) -> bool {
    (7..=40).contains(&value.len()) && value.chars().all(|c| c.is_ascii_hexdigit())
}
