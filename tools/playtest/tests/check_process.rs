use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

static NEXT: AtomicU64 = AtomicU64::new(0);

struct Fixture(PathBuf);

impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "fragr check process-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn run(&self, mode: &str, timeout: &str) -> Output {
        self.run_executable(mode, timeout, std::env::current_exe().unwrap())
    }

    fn run_executable(&self, mode: &str, timeout: &str, executable: PathBuf) -> Output {
        Command::new(env!("CARGO_BIN_EXE_fragr-check-process"))
            .args(["--timeout-ms", timeout, "--output"])
            .arg(self.0.join("output.log"))
            .arg("--")
            .arg(executable)
            .args(["--exact", "guard_fixture_child", "--nocapture"])
            .env("FRAGR_GUARD_FIXTURE_MODE", mode)
            .env("FRAGR_GUARD_FIXTURE_DIR", &self.0)
            .output()
            .unwrap()
    }

    fn log(&self) -> String {
        fs::read_to_string(self.0.join("output.log")).unwrap()
    }

    fn await_marker(&self, name: &str) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while !self.0.join(name).exists() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(self.0.join(name).exists(), "missing child marker {name}");
    }
}

#[test]
fn launches_an_executable_and_retains_output_under_paths_with_spaces() {
    let fixture = Fixture::new();
    let executable = fixture.0.join(if cfg!(windows) {
        "engine with spaces.exe"
    } else {
        "engine with spaces"
    });
    fs::copy(std::env::current_exe().unwrap(), &executable).unwrap();
    assert!(fixture
        .run_executable("success", "5000", executable)
        .status
        .success());
    assert!(fixture.log().contains("fixture: PASS"));
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

// This test executable also supplies real cross-platform child processes.
#[test]
// The two descendant fixtures deliberately outlive their parent to exercise
// inherited output and lease cleanup. The enclosing tests await their exit.
#[allow(clippy::zombie_processes)]
fn guard_fixture_child() {
    let Ok(mode) = std::env::var("FRAGR_GUARD_FIXTURE_MODE") else {
        return;
    };
    let directory = PathBuf::from(std::env::var_os("FRAGR_GUARD_FIXTURE_DIR").unwrap());
    match mode.as_str() {
        "success" => println!("fixture: PASS"),
        "failure" => {
            eprintln!("fixture: failing child diagnostic");
            std::process::exit(7);
        }
        "hang" => {
            println!("fixture: PASS");
            std::io::stdout().flush().unwrap();
            loop {
                std::thread::sleep(Duration::from_secs(1));
            }
        }
        "inherited_output" | "tree" => {
            let mut child = Command::new(std::env::current_exe().unwrap())
                .args(["--exact", "guard_fixture_child", "--nocapture"])
                .env(
                    "FRAGR_GUARD_FIXTURE_MODE",
                    if mode == "tree" {
                        "lease"
                    } else {
                        "hold_output"
                    },
                )
                .stdin(Stdio::piped())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .spawn()
                .unwrap();
            fs::write(directory.join("descendant.pid"), child.id().to_string()).unwrap();
            println!("fixture: descendant launched");
            std::io::stdout().flush().unwrap();
            if mode == "tree" {
                // The lease closes when the parent dies, as for the local server.
                std::mem::forget(child);
                loop {
                    std::thread::sleep(Duration::from_secs(1));
                }
            }
            drop(child.stdin.take());
        }
        "hold_output" => {
            std::thread::sleep(Duration::from_secs(2));
            fs::write(directory.join("descendant.done"), b"finished").unwrap();
        }
        "lease" => {
            let mut bytes = Vec::new();
            std::io::stdin().read_to_end(&mut bytes).unwrap();
            fs::write(directory.join("descendant.done"), b"lease closed").unwrap();
        }
        _ => panic!("unknown fixture mode"),
    }
}

#[test]
fn preserves_success_and_nonzero_diagnostics() {
    let fixture = Fixture::new();
    assert!(fixture.run("success", "5000").status.success());
    assert!(fixture.log().contains("fixture: PASS"));
    assert_eq!(fixture.run("failure", "5000").status.code(), Some(7));
    assert!(fixture.log().contains("failing child diagnostic"));
    assert!(
        !fixture.log().contains("fixture: PASS"),
        "output is replaced"
    );
}

#[test]
fn pass_before_timeout_is_still_a_failure() {
    let fixture = Fixture::new();
    let result = fixture.run("hang", "1500");
    assert_eq!(result.status.code(), Some(124));
    assert!(fixture.log().contains("fixture: PASS"));
    assert!(String::from_utf8_lossy(&result.stderr).contains("CHECK TIMEOUT"));
}

#[test]
fn refuses_an_unbounded_zero_deadline_before_launch() {
    let fixture = Fixture::new();
    assert!(!fixture.run("success", "0").status.success());
    assert!(!fixture.0.join("output.log").exists());
}

#[test]
fn inherited_output_does_not_hold_the_guard_open() {
    let fixture = Fixture::new();
    // The descendant holds stdout longer than the command's whole deadline.
    let result = fixture.run("inherited_output", "1500");
    assert!(result.status.success(), "{result:?}");
    assert!(fixture.log().contains("descendant launched"));
    fixture.await_marker("descendant.done");
}

#[test]
fn timeout_retires_the_owned_descendant() {
    let fixture = Fixture::new();
    assert_eq!(fixture.run("tree", "1500").status.code(), Some(124));
    #[cfg(not(windows))]
    fixture.await_marker("descendant.done");
    #[cfg(windows)]
    {
        let pid = fs::read_to_string(fixture.0.join("descendant.pid")).unwrap();
        let status = Command::new("tasklist.exe")
            .args(["/FI", &format!("PID eq {pid}"), "/FO", "CSV", "/NH"])
            .output()
            .unwrap();
        assert!(status.status.success());
        assert!(
            !String::from_utf8_lossy(&status.stdout).contains(&format!("\"{pid}\"")),
            "the owned descendant survived timeout"
        );
    }
}
