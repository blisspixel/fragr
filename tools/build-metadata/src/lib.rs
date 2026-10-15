// Shared build metadata. Each binary crate calls this so `--version`,
// `/status` `build.release`, and the MCP `serverInfo.version` are one string:
// `FRAGR_BUILD_VERSION` when a release build sets it, otherwise
// `git describe --tags --always`.

use std::process::Command;

pub fn emit() {
    let commit = nonempty("FRAGR_BUILD_COMMIT").or_else(|| git(&["rev-parse", "HEAD"]));
    let release = nonempty("FRAGR_BUILD_VERSION")
        .and_then(|value| release_token(&value))
        .or_else(|| {
            git(&["describe", "--tags", "--always", "--abbrev=12"])
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
    // HEAD is usually a symbolic ref: advancing a branch leaves HEAD itself
    // unchanged. Git resolves shared refs correctly for linked worktrees too.
    // Watching refs also catches new/deleted tags that change `git describe`.
    // Do not watch the whole git directory: Cargo recursively scans directories,
    // and object writes unrelated to build identity would invalidate the build.
    for name in ["HEAD", "refs", "packed-refs"] {
        if let Some(path) = git(&["rev-parse", "--git-path", name]) {
            let path = std::path::Path::new(&path);
            // A nonexistent watched file makes Cargo rerun on every build.
            // Packing loose refs changes the watched refs directory, at which
            // point the newly created packed-refs file is registered as well.
            if path.exists() {
                println!("cargo:rerun-if-changed={}", path.display());
            }
        }
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
    let output = Command::new("git")
        .args(args)
        .current_dir(dir)
        .output()
        .ok()?;
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
