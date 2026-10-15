//! Exercise Cargo's actual build-script cache, not a simulated ref watcher.
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
    time::{SystemTime, UNIX_EPOCH},
};

struct Fixture(PathBuf);
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn run(command: &mut Command) -> Output {
    let output = command.output().expect("start fixture command");
    assert!(
        output.status.success(),
        "fixture command failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

fn git(dir: &Path, args: &[&str]) -> String {
    let output = run(Command::new("git")
        .current_dir(dir)
        .args(args)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env(
            "GIT_CONFIG_GLOBAL",
            if cfg!(windows) { "NUL" } else { "/dev/null" },
        )
        .env_remove("GIT_DIR")
        .env_remove("GIT_WORK_TREE")
        .env_remove("GIT_INDEX_FILE")
        .env_remove("GIT_COMMON_DIR"));
    String::from_utf8(output.stdout).unwrap().trim().to_owned()
}

fn commit(dir: &Path, message: &str) -> String {
    git(
        dir,
        &[
            "-c",
            "user.name=Nick Seal",
            "-c",
            "user.email=32712898+blisspixel@users.noreply.github.com",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "--quiet",
            "--allow-empty",
            "-m",
            message,
        ],
    );
    git(dir, &["rev-parse", "HEAD"])
}

fn build(dir: &Path, version: Option<&str>, commit: Option<&str>) -> (String, String) {
    build_in(dir, &dir.join("target"), version, commit)
}

fn build_in(
    dir: &Path,
    target: &Path,
    version: Option<&str>,
    commit: Option<&str>,
) -> (String, String) {
    let mut cmd = Command::new(std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into()));
    cmd.current_dir(dir)
        .args(["build", "--offline", "--locked", "-vv"])
        .env("CARGO_TARGET_DIR", target)
        // Cache assertions read Cargo's labels; CI forces ANSI color globally.
        .env("CARGO_TERM_COLOR", "never")
        .env_remove("FRAGR_BUILD_VERSION")
        .env_remove("FRAGR_BUILD_COMMIT")
        .env_remove("GIT_DIR")
        .env_remove("GIT_WORK_TREE")
        .env_remove("GIT_INDEX_FILE")
        .env_remove("GIT_COMMON_DIR")
        .env_remove("RUSTFLAGS")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .env_remove("LLVM_PROFILE_FILE")
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER");
    if let Some(value) = version {
        cmd.env("FRAGR_BUILD_VERSION", value);
    }
    if let Some(value) = commit {
        cmd.env("FRAGR_BUILD_COMMIT", value);
    }
    let output = run(&mut cmd);
    let executable = target
        .join("debug")
        .join(format!("metadata-fixture{}", std::env::consts::EXE_SUFFIX));
    let identity = run(&mut Command::new(executable));
    (
        String::from_utf8(identity.stdout)
            .unwrap()
            .trim()
            .to_owned(),
        String::from_utf8(output.stderr).unwrap(),
    )
}

fn write_package(package: &Path, library: &Path, dependency_path: &str) {
    fs::create_dir_all(package.join("src")).unwrap();
    fs::create_dir_all(library.join("src")).unwrap();
    fs::write(package.join("Cargo.toml"), format!("[package]\nname = \"metadata-fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n[build-dependencies]\nfragr-build-metadata = {{ path = \"{dependency_path}\" }}\n")).unwrap();
    fs::write(package.join("Cargo.lock"), "version = 4\n\n[[package]]\nname = \"fragr-build-metadata\"\nversion = \"0.1.0\"\n\n[[package]]\nname = \"metadata-fixture\"\nversion = \"0.1.0\"\ndependencies = [\"fragr-build-metadata\"]\n").unwrap();
    fs::write(package.join("build.rs"), include_str!("../build.rs")).unwrap();
    fs::write(
        library.join("Cargo.toml"),
        "[package]\nname = \"fragr-build-metadata\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    fs::write(
        library.join("src/lib.rs"),
        include_str!("../../tools/build-metadata/src/lib.rs"),
    )
    .unwrap();
    fs::write(package.join("src/main.rs"), "fn main() { println!(\"{} {}\", env!(\"FRAGR_CLI_VERSION\"), option_env!(\"FRAGR_BUILD_COMMIT\").unwrap_or(\"unknown\")); }\n").unwrap();
}

#[test]
fn shared_target_rebinds_metadata_dependency_to_the_current_worktree() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = Fixture(std::env::temp_dir().join(format!(
        "fragr-build-include-{}-{unique}",
        std::process::id()
    )));
    let repo = root.0.join("repo");
    let package = repo.join("server");
    let library = repo.join("tools/build-metadata");
    write_package(&package, &library, "../tools/build-metadata");
    let shared = include_str!("../../tools/build-metadata/src/lib.rs");
    git(&repo, &["init", "--quiet", "-b", "fixture"]);
    git(&repo, &["add", "."]);
    let first = commit(&repo, "shared include fixture");
    git(&repo, &["tag", "v1.0.0"]);
    let linked = root.0.join("linked");
    git(
        &repo,
        &[
            "worktree",
            "add",
            "--quiet",
            "-b",
            "linked",
            linked.to_str().unwrap(),
        ],
    );
    let target = root.0.join("shared-target");
    assert_eq!(
        build_in(&linked.join("server"), &target, None, None).0,
        format!("v1.0.0 {first}")
    );
    // Keep the branch refs and both package-local wrappers unchanged. Only
    // this worktree's build dependency changes after the other build.
    let changed = shared.replace(
        "println!(\"cargo:rustc-env=FRAGR_CLI_VERSION={cli}\");",
        "println!(\"cargo:rustc-env=FRAGR_CLI_VERSION=fixture-updated\");",
    );
    assert_ne!(changed, shared);
    fs::write(library.join("src/lib.rs"), changed).unwrap();
    assert_eq!(
        build_in(&package, &target, None, None).0,
        format!("fixture-updated {first}"),
        "shared target must compile this worktree's dependency source"
    );
    assert!(build_in(&package, &target, None, None)
        .1
        .contains("Fresh metadata-fixture"));
    assert_eq!(
        build_in(&linked.join("server"), &target, None, None).0,
        format!("v1.0.0 {first}"),
        "switching back must restore the other worktree's actual source"
    );
}

#[test]
fn cargo_refreshes_identity_for_branch_tags_packed_refs_and_worktrees() {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = Fixture(std::env::temp_dir().join(format!(
        "fragr-build-metadata-{}-{unique}",
        std::process::id()
    )));
    let repo = root.0.join("repo");
    write_package(&repo, &repo.join("build-metadata"), "build-metadata");
    fs::write(repo.join(".gitignore"), "target/\n").unwrap();
    git(&repo, &["init", "--quiet", "-b", "fixture"]);
    git(&repo, &["add", "."]);
    let first = commit(&repo, "fixture baseline");
    git(&repo, &["tag", "v1.0.0"]);
    assert_eq!(build(&repo, None, None).0, format!("v1.0.0 {first}"));
    assert!(build(&repo, None, None)
        .1
        .contains("Fresh metadata-fixture"));
    let second = commit(&repo, "fixture branch advance");
    let changed = build(&repo, None, None).0;
    assert_eq!(
        changed,
        format!("v1.0.0-1-g{} {second}", &second[..12]),
        "same-branch commit must refresh cached identity"
    );
    git(&repo, &["tag", "v1.1.0"]);
    assert_eq!(build(&repo, None, None).0, format!("v1.1.0 {second}"));
    git(&repo, &["pack-refs", "--all", "--prune"]);
    assert_eq!(build(&repo, None, None).0, format!("v1.1.0 {second}"));
    git(&repo, &["tag", "-d", "v1.1.0"]);
    assert_eq!(
        build(&repo, None, None).0,
        changed,
        "packed tag deletion must invalidate describe"
    );
    let third = commit(&repo, "fixture packed branch advance");
    assert_eq!(
        build(&repo, None, None).0,
        format!("v1.0.0-2-g{} {third}", &third[..12])
    );
    let linked = root.0.join("linked");
    git(
        &repo,
        &[
            "worktree",
            "add",
            "--quiet",
            "-b",
            "linked",
            linked.to_str().unwrap(),
        ],
    );
    assert_eq!(
        build(&linked, None, None).0,
        format!("v1.0.0-2-g{} {third}", &third[..12])
    );
    let fourth = commit(&linked, "fixture linked branch advance");
    assert_eq!(
        build(&linked, None, None).0,
        format!("v1.0.0-3-g{} {fourth}", &fourth[..12])
    );
    git(&linked, &["tag", "v2.0.0"]);
    assert_eq!(build(&linked, None, None).0, format!("v2.0.0 {fourth}"));
    let unchanged = build(&linked, None, None);
    assert!(
        unchanged.1.contains("Fresh metadata-fixture"),
        "unchanged build should reuse cache: {}",
        unchanged.1
    );
    assert_eq!(
        build(&linked, Some("v9.0.0"), Some("1234567890abcdef")).0,
        "v9.0.0 1234567890abcdef"
    );
    assert_eq!(build(&linked, None, None).0, format!("v2.0.0 {fourth}"));
    git(&linked, &["checkout", "--quiet", "--detach", &first]);
    assert_eq!(build(&linked, None, None).0, format!("v1.0.0 {first}"));
    // Distribution archives have no Git administration or repository identity.
    let archive = root.0.join("archive");
    write_package(&archive, &archive.join("build-metadata"), "build-metadata");
    assert_eq!(build(&archive, None, None).0, "0.1.0 unknown");
}
