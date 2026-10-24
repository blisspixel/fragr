//! The real dedicated executable's terminal output: redirected log, forced
//! overview, colour gate, the desk's `status`, closed operator input, and a
//! refused bind. A pseudo-terminal `auto` run is recorded in the plan.
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{channel, Receiver};
use std::time::{Duration, Instant};

struct Server {
    child: Child,
    stdout: Receiver<String>,
    stderr: Receiver<String>,
    out: Vec<String>,
    err: Vec<String>,
}

impl Server {
    fn start(args: &[&str], env: &[(&str, &str)]) -> Self {
        let mut command = Command::new(env!("CARGO_BIN_EXE_fragr-server"));
        command
            .args(["--bind", "127.0.0.1:0", "--seed", "7"])
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .env_remove("RUST_LOG")
            .env_remove("NO_COLOR")
            .env_remove("FORCE_COLOR")
            .env_remove("FRAGR_JOIN_SECRET");
        for (key, value) in env {
            command.env(key, value);
        }
        let mut child = command.spawn().expect("spawn fragr-server");
        let stdout = lines(child.stdout.take().unwrap());
        let stderr = lines(child.stderr.take().unwrap());
        Self {
            child,
            stdout,
            stderr,
            out: Vec::new(),
            err: Vec::new(),
        }
    }

    fn drain(&mut self) {
        self.out.extend(self.stdout.try_iter());
        self.err.extend(self.stderr.try_iter());
    }

    /// Wait until `found` holds for the collected output, or fail with it.
    fn wait_for(&mut self, what: &str, bound: Duration, found: impl Fn(&Self) -> bool) {
        let deadline = Instant::now() + bound;
        loop {
            self.drain();
            if found(self) {
                return;
            }
            if Instant::now() > deadline {
                panic!(
                    "timed out waiting for {what}\nstdout:\n{}\nstderr:\n{}",
                    self.out.join("\n"),
                    self.err.join("\n")
                );
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    fn stdout_has(&self, needle: &str) -> bool {
        self.out.iter().any(|line| line.contains(needle))
    }

    fn stderr_has(&self, needle: &str) -> bool {
        self.err.iter().any(|line| line.contains(needle))
    }

    fn all(&self) -> String {
        format!("{}\n{}", self.out.join("\n"), self.err.join("\n"))
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn lines(stream: impl std::io::Read + Send + 'static) -> Receiver<String> {
    let (tx, rx) = channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stream).lines() {
            let Ok(line) = line else { break };
            if tx.send(line).is_err() {
                break;
            }
        }
    });
    rx
}

const READY: Duration = Duration::from_secs(60);

#[test]
fn redirected_output_keeps_the_full_plain_log() {
    let mut server = Server::start(&["--status-every-s", "1"], &[]);
    server.wait_for("ready line", READY, |s| {
        s.stdout_has("ready ws://127.0.0.1:")
    });
    server.wait_for("STATUS JSON", READY, |s| s.stderr_has("STATUS {"));
    assert!(
        server.stderr_has("fragr_server::feed: Spawned bot:"),
        "{}",
        server.all()
    );
    assert!(
        server.stderr_has("fragr_server::startup: Map: Arena Duel"),
        "{}",
        server.all()
    );
    assert!(
        !server.stdout_has("fragr dedicated server"),
        "no card when redirected"
    );
    assert!(!server.stdout_has("running |"), "no pulse when redirected");
    assert!(
        !server.all().contains('\x1b'),
        "no escapes:\n{}",
        server.all()
    );
}

#[test]
fn forced_overview_prints_a_card_and_pulses_without_the_feed() {
    // NO_COLOR beats FORCE_COLOR under auto colour, on both streams.
    let mut server = Server::start(
        &["--output", "overview", "--status-every-s", "1"],
        &[("NO_COLOR", "1"), ("FORCE_COLOR", "1")],
    );
    server.wait_for("ready line", READY, |s| {
        s.stdout_has("ready ws://127.0.0.1:")
    });
    server.wait_for("pulse with bots", READY, |s| {
        s.out
            .iter()
            .any(|line| line.contains("running |") && line.contains("4 bots"))
    });
    // Two periodic pulses prove the cadence, not a single startup line.
    server.wait_for("second pulse", READY, |s| {
        s.out
            .iter()
            .filter(|line| line.contains("running |"))
            .count()
            >= 2
    });
    let ready = server
        .out
        .iter()
        .position(|line| line.starts_with("ready ws://"))
        .unwrap();
    assert!(
        server.out[ready + 1].starts_with("fragr dedicated server"),
        "card follows the unchanged ready line:\n{}",
        server.out.join("\n")
    );
    for needle in [
        "No game window",
        "Arena Duel, Free-for-all.",
        "Bots: 4 fixed rule bots",
        "local   ws://127.0.0.1:",
        "Other computers cannot join a loopback bind",
        "Restart with --console",
        "Ctrl-C, or close this window",
        "--output log",
    ] {
        assert!(
            server.stdout_has(needle),
            "missing {needle:?}:\n{}",
            server.all()
        );
    }
    for hidden in [
        "Spawned bot",
        "FRAG:",
        "PICKUP:",
        "STATUS {",
        "Map: Arena Duel",
    ] {
        assert!(
            !server.all().contains(hidden),
            "{hidden:?} shown:\n{}",
            server.all()
        );
    }
    assert!(
        !server.all().contains('\x1b'),
        "no escapes:\n{}",
        server.all()
    );
}

#[test]
fn explicit_colour_reaches_the_card_and_never_magenta() {
    let mut server = Server::start(
        &[
            "--output",
            "overview",
            "--color",
            "always",
            "--status-every-s",
            "0",
        ],
        &[],
    );
    server.wait_for("pulse", READY, |s| s.stdout_has("running"));
    assert!(server.stdout_has("\x1b[1m"), "{}", server.all());
    assert!(!server.all().contains("\x1b[35m"), "{}", server.all());
}

#[test]
fn desk_status_answers_and_closed_input_leaves_the_match_running() {
    let mut server = Server::start(&["--output", "overview", "--console"], &[]);
    server.wait_for("desk banner", READY, |s| {
        s.stdout_has("Venue desk. help, status")
    });
    assert!(
        server.stdout_has("On. Type help, status"),
        "{}",
        server.all()
    );
    let mut stdin = server.child.stdin.take().unwrap();
    // Let the four bots join so the room table has rows.
    server.wait_for("first pulse", READY, |s| s.stdout_has("4 bots"));
    writeln!(stdin, "status").unwrap();
    stdin.flush().unwrap();
    server.wait_for("status answer", READY, |s| {
        s.out
            .iter()
            .filter(|line| line.contains("running |"))
            .count()
            >= 2
            && s.stdout_has("local ws://127.0.0.1:")
    });
    drop(stdin);
    server.wait_for("desk closed", READY, |s| {
        s.stdout_has("Venue desk closed. The match keeps running.")
    });
    std::thread::sleep(Duration::from_millis(500));
    assert!(
        server.child.try_wait().unwrap().is_none(),
        "closing operator input must not stop the server:\n{}",
        server.all()
    );
}

#[test]
fn a_taken_port_fails_with_one_line_and_no_card() {
    let holder = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = holder.local_addr().unwrap().port();
    let output = Command::new(env!("CARGO_BIN_EXE_fragr-server"))
        .args([
            "--bind",
            &format!("127.0.0.1:{port}"),
            "--output",
            "overview",
        ])
        .env_remove("RUST_LOG")
        .stdin(Stdio::null())
        .output()
        .unwrap();
    assert!(!output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(!stdout.contains("ready ws://"), "{stdout}");
    assert!(!stdout.contains("fragr dedicated server"), "{stdout}");
    assert!(stderr.contains(&port.to_string()), "{stderr}");
    assert_eq!(
        stderr
            .lines()
            .filter(|line| !line.trim().is_empty())
            .count(),
        1,
        "one error line, nothing else:\n{stderr}"
    );
    assert!(!stderr.contains('\x1b'), "{stderr}");
    drop(holder);
}

#[test]
fn a_watcher_changes_the_room_line_and_the_join_event_stays_visible() {
    use futures_util::{SinkExt, StreamExt};
    let mut server = Server::start(&["--output", "overview", "--status-every-s", "0"], &[]);
    server.wait_for("ready line", READY, |s| {
        s.stdout_has("ready ws://127.0.0.1:")
    });
    server.wait_for("bots in the room", READY, |s| {
        s.stdout_has("4 bots, 0 watching")
    });
    let url = server
        .out
        .iter()
        .find_map(|line| {
            line.strip_prefix("ready ")
                .and_then(|rest| rest.split(' ').next())
        })
        .unwrap()
        .to_string();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let mut socket = runtime.block_on(async {
        let (mut socket, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
        let hello = serde_json::json!({
            "type": "hello", "role": "spectator", "name": "Watcher",
            "gameplay_version": fragr_server::protocol::GAMEPLAY_VERSION,
            "geometry_version": fragr_server::protocol::GEOMETRY_VERSION,
        });
        socket
            .send(tokio_tungstenite::tungstenite::Message::Text(
                hello.to_string(),
            ))
            .await
            .unwrap();
        socket
    });
    // Keep reading so the watcher is a live reader, not a stalled one.
    let reader = runtime.spawn(async move { while socket.next().await.is_some() {} });
    server.wait_for("a watcher in the pulse", READY, |s| {
        s.stdout_has("4 bots, 1 watching")
    });
    assert!(
        server.stderr_has("Spectator Watcher joined"),
        "{}",
        server.all()
    );
    assert!(
        !server.all().contains("New connection from"),
        "{}",
        server.all()
    );
    reader.abort();
}
