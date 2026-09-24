//! Soak harness: a real server with rule bots, reflex agents and spectators
//! for a fixed time, sampled through `GET /status?clients=1` and the server
//! process's resident set, written as NDJSON and checked at the end.
//!
//! The server is normally the `fragr-server` binary as a child process, so a
//! crash is a real exit and memory is the server's own. It is stopped through
//! its own process handle, never by name or port.

use super::{agent_task, transport, Error, Policy};
use fragr_server::protocol::{ClientMessage, HealthState, LiveStatus, Role, ServerMessage};
use fragr_server::sim::MapKind;
use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::watch;
use tokio_tungstenite::{connect_async, tungstenite::Message};

/// NDJSON line format. Bumped when a field changes meaning.
pub const SOAK_SCHEMA: u32 = 1;
/// The tick budget the p99 must stay under.
pub const TICK_BUDGET_MS: f64 = 50.0;
/// Resident set growth allowed from the first sample to the last: half the
/// first sample or 64 MiB, whichever is larger.
pub const RSS_GROWTH_FRACTION: f64 = 0.5;
pub const RSS_GROWTH_FLOOR: u64 = 64 * 1024 * 1024;
/// The per-address cap on loopback, less one for the status probe.
pub const MAX_SOAK_CLIENTS: usize = 31;

/// How the server under test runs.
#[derive(Debug, Clone)]
pub enum Launch {
    /// The dedicated binary as a child process.
    Binary(PathBuf),
    /// `run_server` inside this process. Tests only: a crash takes the harness
    /// with it and memory includes the clients.
    InProcess,
}

#[derive(Debug, Clone)]
pub struct SoakConfig {
    pub seconds: u64,
    pub sample_seconds: u64,
    pub bots: usize,
    pub agents: usize,
    pub spectators: usize,
    pub map: MapKind,
    pub map_rotate: bool,
    pub seed: u64,
    pub launch: Launch,
    pub log: PathBuf,
}

impl SoakConfig {
    pub fn validate(&self) -> Result<(), Error> {
        if self.seconds == 0 || self.sample_seconds == 0 {
            return Err(Error::Server(
                "soak and sample seconds must be positive".into(),
            ));
        }
        if self.sample_seconds > self.seconds {
            return Err(Error::Server(
                "sample interval is longer than the soak".into(),
            ));
        }
        if self.agents + self.spectators == 0 || self.agents + self.spectators > MAX_SOAK_CLIENTS {
            return Err(Error::Server(format!(
                "agents plus spectators must be 1 through {MAX_SOAK_CLIENTS}"
            )));
        }
        Ok(())
    }
}

/// The resident set of a process, and which OS tool reported it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Rss {
    pub bytes: u64,
    pub source: &'static str,
}

/// `VmRSS:   12345 kB` from `/proc/<pid>/status`.
pub fn parse_proc_status(text: &str) -> Option<u64> {
    let line = text.lines().find(|line| line.starts_with("VmRSS:"))?;
    let kib: u64 = line.split_ascii_whitespace().nth(1)?.parse().ok()?;
    Some(kib * 1024)
}

/// `ps -o rss= -p <pid>` prints KiB.
pub fn parse_ps_rss(text: &str) -> Option<u64> {
    let kib: u64 = text.trim().parse().ok()?;
    Some(kib * 1024)
}

/// `tasklist /FI "PID eq <pid>" /FO CSV /NH`: the last column is the working
/// set in KiB with locale digit grouping, for example `"45,678 K"`.
pub fn parse_tasklist_csv(text: &str, pid: u32) -> Option<u64> {
    let wanted = format!("\"{pid}\"");
    let line = text.lines().find(|line| line.contains(&wanted))?;
    let memory = line.rsplit("\",\"").next()?;
    let digits: String = memory.chars().filter(char::is_ascii_digit).collect();
    let kib: u64 = digits.parse().ok()?;
    Some(kib * 1024)
}

/// Sample a process's resident set with the OS's own tool. `Err` says why a
/// figure is unavailable rather than inventing one.
pub fn sample_rss(pid: u32) -> Result<Rss, String> {
    if cfg!(target_os = "linux") {
        let text = std::fs::read_to_string(format!("/proc/{pid}/status"))
            .map_err(|error| format!("/proc unreadable: {error}"))?;
        return parse_proc_status(&text)
            .map(|bytes| Rss {
                bytes,
                source: "proc_status_vmrss",
            })
            .ok_or_else(|| "no VmRSS line".to_string());
    }
    if cfg!(windows) {
        let output = std::process::Command::new("tasklist")
            .args(["/FI", &format!("PID eq {pid}"), "/FO", "CSV", "/NH"])
            .output()
            .map_err(|error| format!("tasklist failed: {error}"))?;
        return parse_tasklist_csv(&String::from_utf8_lossy(&output.stdout), pid)
            .map(|bytes| Rss {
                bytes,
                source: "tasklist_working_set",
            })
            .ok_or_else(|| "tasklist listed no such process".to_string());
    }
    let output = std::process::Command::new("ps")
        .args(["-o", "rss=", "-p", &pid.to_string()])
        .output()
        .map_err(|error| format!("ps failed: {error}"))?;
    parse_ps_rss(&String::from_utf8_lossy(&output.stdout))
        .map(|bytes| Rss {
            bytes,
            source: "ps_rss",
        })
        .ok_or_else(|| "ps listed no such process".to_string())
}

/// One NDJSON sample line.
#[derive(Debug, Clone, Serialize)]
pub struct Sample {
    pub kind: &'static str,
    pub index: usize,
    pub elapsed_s: f64,
    pub unix_ms: u128,
    pub server_alive: bool,
    pub rss: Option<Rss>,
    pub rss_unavailable: Option<String>,
    pub agents_live: usize,
    pub spectators_live: usize,
    pub status: Option<LiveStatus>,
    pub status_error: Option<String>,
}

/// What the soak was asked to keep connected.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Expected {
    pub agents: usize,
    pub spectators: usize,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct TickRow {
    pub p50_ms: f64,
    pub p95_ms: f64,
    pub p99_ms: f64,
    pub max_ms: f64,
    pub count: u64,
    pub over_budget: u64,
}

/// The numbers a plan's measurement table needs.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct SoakSummary {
    pub samples: usize,
    pub measured_s: f64,
    pub ticks_start: u64,
    pub ticks_end: u64,
    /// Simulation ticks per second between the first and last sample (nominal 20).
    pub tick_rate_hz: f64,
    pub window_start: TickRow,
    pub window_end: TickRow,
    pub lifetime_end: TickRow,
    pub out_bytes_per_client_per_s: f64,
    pub in_bytes_per_client_per_s: f64,
    pub queue_overflows: u64,
    pub degraded_samples: usize,
    pub rss_start: Option<u64>,
    pub rss_end: Option<u64>,
    pub rss_max: Option<u64>,
    pub rss_source: Option<&'static str>,
    pub build_commit: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Verdict {
    pub kind: &'static str,
    pub schema: u32,
    pub passed: bool,
    pub problems: Vec<String>,
    pub notes: Vec<String>,
    pub summary: SoakSummary,
}

fn tick_row(summary: &fragr_server::protocol::TickSummary) -> TickRow {
    TickRow {
        p50_ms: summary.p50_ms,
        p95_ms: summary.p95_ms,
        p99_ms: summary.p99_ms,
        max_ms: summary.max_ms,
        count: summary.count,
        over_budget: summary.over_budget,
    }
}

/// Every rule the soak enforces, as complaints naming the sample.
pub fn check_soak(samples: &[Sample], expected: Expected) -> Verdict {
    let mut problems = Vec::new();
    let mut notes = Vec::new();
    let mut summary = SoakSummary {
        samples: samples.len(),
        ..SoakSummary::default()
    };
    if samples.len() < 2 {
        problems.push(format!(
            "{} samples; a soak needs a start and an end",
            samples.len()
        ));
    }
    let mut previous_tick: Option<u64> = None;
    for sample in samples {
        let at = format!("sample {} ({:.0} s)", sample.index, sample.elapsed_s);
        if !sample.server_alive {
            problems.push(format!("{at}: the server process had exited"));
        }
        if sample.agents_live != expected.agents || sample.spectators_live != expected.spectators {
            problems.push(format!(
                "{at}: {} of {} agents and {} of {} spectators still connected",
                sample.agents_live, expected.agents, sample.spectators_live, expected.spectators
            ));
        }
        let Some(status) = &sample.status else {
            problems.push(format!(
                "{at}: no status ({})",
                sample.status_error.as_deref().unwrap_or("no answer")
            ));
            continue;
        };
        if let Some(previous) = previous_tick {
            if status.tick <= previous {
                problems.push(format!(
                    "{at}: tick {} did not advance past {previous}",
                    status.tick
                ));
            }
        }
        previous_tick = Some(status.tick);
        let wanted = expected.agents + expected.spectators;
        if status.connections != wanted {
            problems.push(format!(
                "{at}: server counts {} connections, expected {wanted}",
                status.connections
            ));
        }
        let Some(ops) = &status.ops else {
            problems.push(format!("{at}: status has no operator block"));
            continue;
        };
        if ops.connections.agents != expected.agents
            || ops.connections.spectators != expected.spectators
        {
            problems.push(format!(
                "{at}: server counts {} agents and {} spectators",
                ops.connections.agents, ops.connections.spectators
            ));
        }
        if let Some(health) = &status.health {
            if health.status == HealthState::Degraded {
                summary.degraded_samples += 1;
                problems.push(format!("{at}: health degraded {:?}", health.reasons));
            }
        }
    }
    let with_status: Vec<(&Sample, &LiveStatus)> = samples
        .iter()
        .filter_map(|sample| sample.status.as_ref().map(|status| (sample, status)))
        .filter(|(_, status)| status.ops.is_some())
        .collect();
    if let (Some((first, start)), Some((last, end))) = (with_status.first(), with_status.last()) {
        let (start_ops, end_ops) = (start.ops.as_ref().unwrap(), end.ops.as_ref().unwrap());
        summary.measured_s = last.elapsed_s - first.elapsed_s;
        summary.ticks_start = start.tick;
        summary.ticks_end = end.tick;
        summary.window_start = tick_row(&start_ops.tick.window);
        summary.window_end = tick_row(&end_ops.tick.window);
        summary.lifetime_end = tick_row(&end_ops.tick.lifetime);
        summary.queue_overflows = end_ops.traffic.queue_overflows_total;
        summary.build_commit = Some(end_ops.build.commit.clone());
        let clients = (expected.agents + expected.spectators).max(1) as f64;
        if summary.measured_s > 0.0 {
            let per = |end: u64, start: u64| {
                end.saturating_sub(start) as f64 / summary.measured_s / clients
            };
            summary.tick_rate_hz = end.tick.saturating_sub(start.tick) as f64 / summary.measured_s;
            summary.out_bytes_per_client_per_s =
                per(end_ops.traffic.out_bytes, start_ops.traffic.out_bytes);
            summary.in_bytes_per_client_per_s =
                per(end_ops.traffic.in_bytes, start_ops.traffic.in_bytes);
        }
        if end_ops.tick.lifetime.p99_ms >= TICK_BUDGET_MS {
            problems.push(format!(
                "lifetime p99 tick {:.2} ms is not under the {TICK_BUDGET_MS} ms budget",
                end_ops.tick.lifetime.p99_ms
            ));
        }
        if end_ops.traffic.queue_overflows_total > 0 {
            problems.push(format!(
                "{} outbound queue overflows",
                end_ops.traffic.queue_overflows_total
            ));
        }
    }
    let rss: Vec<Rss> = samples.iter().filter_map(|sample| sample.rss).collect();
    match (rss.first(), rss.last()) {
        (Some(first), Some(last)) if rss.len() == samples.len() => {
            summary.rss_start = Some(first.bytes);
            summary.rss_end = Some(last.bytes);
            summary.rss_max = rss.iter().map(|rss| rss.bytes).max();
            summary.rss_source = Some(first.source);
            let allowed = ((first.bytes as f64 * RSS_GROWTH_FRACTION) as u64).max(RSS_GROWTH_FLOOR);
            let grown = last.bytes.saturating_sub(first.bytes);
            if grown > allowed {
                problems.push(format!(
                    "resident set grew {} MiB, more than the {} MiB allowed",
                    grown / (1024 * 1024),
                    allowed / (1024 * 1024)
                ));
            }
        }
        _ => notes.push(format!(
            "resident set unavailable for {} of {} samples; memory growth not checked",
            samples.len() - rss.len(),
            samples.len()
        )),
    }
    Verdict {
        kind: "verdict",
        schema: SOAK_SCHEMA,
        passed: problems.is_empty(),
        problems,
        notes,
        summary,
    }
}

/// `GET <path>` on the game port, parsed as the status line.
pub async fn fetch_status(address: std::net::SocketAddr, path: &str) -> Result<LiveStatus, Error> {
    let exchange = async {
        let mut tcp = tokio::net::TcpStream::connect(address).await?;
        tcp.write_all(format!("GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n").as_bytes())
            .await?;
        let mut response = Vec::new();
        tcp.read_to_end(&mut response).await?;
        Ok::<_, std::io::Error>(response)
    };
    let response = tokio::time::timeout(Duration::from_secs(5), exchange)
        .await
        .map_err(|_| Error::Timeout("status answer"))??;
    let text = String::from_utf8_lossy(&response);
    let (head, body) = text
        .split_once("\r\n\r\n")
        .ok_or_else(|| Error::Server("status answer has no body".into()))?;
    if !head.starts_with("HTTP/1.1 200") {
        return Err(Error::Server("status answer is not 200".into()));
    }
    serde_json::from_str(body).map_err(transport)
}

#[derive(Debug, Default)]
struct WatchOutcome {
    snapshots: u64,
    disconnected: bool,
}

async fn spectator_task(
    url: String,
    name: String,
    ready: tokio::sync::oneshot::Sender<()>,
    mut stop: watch::Receiver<bool>,
) -> Result<WatchOutcome, Error> {
    let (socket, _) = connect_async(&url).await.map_err(transport)?;
    let (mut sink, mut stream) = socket.split();
    sink.send(Message::Text(
        serde_json::to_string(&ClientMessage::Hello {
            gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
            geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
            role: Role::Spectator,
            name,
            ticket: None,
            resume: None,
        })
        .map_err(transport)?,
    ))
    .await
    .map_err(transport)?;
    let mut ready = Some(ready);
    let mut outcome = WatchOutcome::default();
    loop {
        let message = tokio::select! {
            _ = stop.changed() => break,
            message = stream.next() => message,
        };
        let Some(Ok(message)) = message else {
            outcome.disconnected = !*stop.borrow();
            break;
        };
        if let Message::Text(text) = message {
            if let Ok(ServerMessage::Snapshot(_)) = serde_json::from_str::<ServerMessage>(&text) {
                outcome.snapshots += 1;
                if let Some(ready) = ready.take() {
                    let _ = ready.send(());
                }
            }
        }
    }
    let _ = sink.close().await;
    Ok(outcome)
}

/// The server under test and a way to ask whether it is still running.
enum Running {
    Child(Box<tokio::process::Child>),
    InProcess(
        tokio::task::JoinHandle<Result<(), String>>,
        tokio::sync::oneshot::Sender<()>,
    ),
}

impl Running {
    fn pid(&self) -> Option<u32> {
        match self {
            Running::Child(child) => child.id(),
            Running::InProcess(..) => Some(std::process::id()),
        }
    }

    fn alive(&mut self) -> bool {
        match self {
            Running::Child(child) => matches!(child.try_wait(), Ok(None)),
            Running::InProcess(handle, _) => !handle.is_finished(),
        }
    }

    /// Stop by the handle this harness owns. Returns the exit description.
    async fn stop(self) -> String {
        match self {
            Running::Child(mut child) => {
                if let Ok(Some(status)) = child.try_wait() {
                    return format!("exited on its own: {status}");
                }
                let _ = child.start_kill();
                match tokio::time::timeout(Duration::from_secs(10), child.wait()).await {
                    Ok(Ok(_)) => "stopped by the harness".to_string(),
                    Ok(Err(error)) => format!("wait failed: {error}"),
                    Err(_) => "did not stop within 10 s".to_string(),
                }
            }
            Running::InProcess(handle, stop) => {
                let _ = stop.send(());
                match tokio::time::timeout(Duration::from_secs(10), handle).await {
                    Ok(Ok(Ok(()))) => "stopped by the harness".to_string(),
                    Ok(Ok(Err(error))) => format!("server error: {error}"),
                    Ok(Err(error)) => format!("server task failed: {error}"),
                    Err(_) => "did not stop within 10 s".to_string(),
                }
            }
        }
    }
}

fn free_loopback_port() -> Result<u16, Error> {
    let listener = std::net::TcpListener::bind("127.0.0.1:0")?;
    Ok(listener.local_addr()?.port())
}

async fn start_server(
    config: &SoakConfig,
    server_log: &Path,
) -> Result<(Running, std::net::SocketAddr), Error> {
    match &config.launch {
        Launch::Binary(binary) => {
            let port = free_loopback_port()?;
            let address: std::net::SocketAddr = ([127, 0, 0, 1], port).into();
            let log = std::fs::File::create(server_log)?;
            let mut command = tokio::process::Command::new(binary);
            command
                .arg("--bind")
                .arg(address.to_string())
                .arg("--bots")
                .arg(config.bots.to_string())
                .arg("--map")
                .arg(config.map.id().to_string())
                .arg("--seed")
                .arg(config.seed.to_string())
                .arg("--status-every-s")
                .arg("60")
                .stdin(std::process::Stdio::null())
                .stdout(log.try_clone()?)
                .stderr(log)
                .kill_on_drop(true);
            if config.map_rotate {
                command.arg("--map-rotate");
            }
            let child = command.spawn().map_err(|error| {
                Error::Server(format!("cannot start {}: {error}", binary.display()))
            })?;
            let mut running = Running::Child(Box::new(child));
            let deadline = Instant::now() + Duration::from_secs(60);
            loop {
                if !running.alive() {
                    return Err(Error::Server(format!(
                        "server exited during start; see {}",
                        server_log.display()
                    )));
                }
                if fetch_status(address, "/status").await.is_ok() {
                    return Ok((running, address));
                }
                if Instant::now() > deadline {
                    let _ = running.stop().await;
                    return Err(Error::Timeout("server status at start"));
                }
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
        Launch::InProcess => {
            let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
            let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
            let options = fragr_server::run::ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: config.bots,
                map: config.map,
                map_rotate: config.map_rotate,
                seed: config.seed,
                status_every_s: 0,
                ..fragr_server::run::ServerOptions::default()
            };
            let handle = tokio::spawn(async move {
                fragr_server::run::run_server(
                    options,
                    async move {
                        let _ = stop_rx.await;
                    },
                    Some(ready_tx),
                )
                .await
                .map_err(|error| error.to_string())
            });
            let address = tokio::time::timeout(Duration::from_secs(60), ready_rx)
                .await
                .map_err(|_| Error::Timeout("in-process server bind"))?
                .map_err(|_| Error::Server("in-process server exited before bind".into()))?;
            Ok((Running::InProcess(handle, stop_tx), address))
        }
    }
}

fn unix_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|since| since.as_millis())
        .unwrap_or(0)
}

fn git_commit() -> Option<String> {
    let output = std::process::Command::new("git")
        .args(["rev-parse", "HEAD"])
        .output()
        .ok()?;
    let commit = String::from_utf8(output.stdout).ok()?.trim().to_string();
    (output.status.success() && commit.len() == 40).then_some(commit)
}

#[derive(Serialize)]
struct Header<'a> {
    kind: &'static str,
    schema: u32,
    started_unix_ms: u128,
    seconds: u64,
    sample_seconds: u64,
    bots: usize,
    agents: usize,
    spectators: usize,
    map: &'a str,
    map_rotate: bool,
    seed: u64,
    launch: String,
    server_pid: Option<u32>,
    source_commit: Option<String>,
    os: &'static str,
    arch: &'static str,
    available_parallelism: Option<usize>,
}

fn write_line(log: &mut std::fs::File, value: &impl Serialize) -> Result<(), Error> {
    let line = serde_json::to_string(value).map_err(transport)?;
    writeln!(log, "{line}")?;
    log.flush()?;
    Ok(())
}

/// Run one soak and return its verdict. Samples stream to `config.log` as
/// they are taken, so a harness crash still leaves the evidence so far.
pub async fn run_soak(config: SoakConfig) -> Result<Verdict, Error> {
    config.validate()?;
    if let Some(parent) = config.log.parent().filter(|p| !p.as_os_str().is_empty()) {
        std::fs::create_dir_all(parent)?;
    }
    let server_log = config.log.with_extension("server.log");
    let mut log = std::fs::File::create(&config.log)?;
    let (mut server, address) = start_server(&config, &server_log).await?;
    let started = Instant::now();
    write_line(
        &mut log,
        &Header {
            kind: "start",
            schema: SOAK_SCHEMA,
            started_unix_ms: unix_ms(),
            seconds: config.seconds,
            sample_seconds: config.sample_seconds,
            bots: config.bots,
            agents: config.agents,
            spectators: config.spectators,
            map: config.map.name(),
            map_rotate: config.map_rotate,
            seed: config.seed,
            launch: match &config.launch {
                Launch::Binary(path) => path.display().to_string(),
                Launch::InProcess => "in_process".to_string(),
            },
            server_pid: server.pid(),
            source_commit: git_commit(),
            os: std::env::consts::OS,
            arch: std::env::consts::ARCH,
            available_parallelism: std::thread::available_parallelism().ok().map(usize::from),
        },
    )?;
    let url = format!("ws://{address}");
    let (stop_tx, stop_rx) = watch::channel(false);
    let mut agents = Vec::new();
    let mut ready = Vec::new();
    for index in 0..config.agents {
        let (tx, rx) = tokio::sync::oneshot::channel();
        ready.push(rx);
        agents.push(tokio::spawn(agent_task(
            url.clone(),
            format!("Soak-A{:02}", index + 1),
            Policy::Reflex,
            stop_rx.clone(),
            Some(tx),
        )));
    }
    let mut spectators = Vec::new();
    for index in 0..config.spectators {
        let (tx, rx) = tokio::sync::oneshot::channel();
        ready.push(rx);
        spectators.push(tokio::spawn(spectator_task(
            url.clone(),
            format!("Soak-S{:02}", index + 1),
            tx,
            stop_rx.clone(),
        )));
    }
    for rx in ready {
        if tokio::time::timeout(Duration::from_secs(60), rx)
            .await
            .map(|ready| ready.is_err())
            .unwrap_or(true)
        {
            let _ = stop_tx.send(true);
            let _ = server.stop().await;
            return Err(Error::Timeout("soak clients ready"));
        }
    }
    // Let one status refresh see every session before the first sample.
    tokio::time::sleep(Duration::from_millis(1500)).await;
    let measured = Instant::now();
    let mut samples = Vec::new();
    let total = Duration::from_secs(config.seconds);
    let interval = Duration::from_secs(config.sample_seconds);
    let mut next = measured;
    loop {
        let elapsed = measured.elapsed();
        let last = elapsed >= total;
        let (status, status_error) = match fetch_status(address, "/status?clients=1").await {
            Ok(status) => (Some(status), None),
            Err(error) => (None, Some(error.to_string())),
        };
        let (rss, rss_unavailable) = match server.pid().map(sample_rss) {
            Some(Ok(rss)) => (Some(rss), None),
            Some(Err(reason)) => (None, Some(reason)),
            None => (None, Some("no process id".to_string())),
        };
        let sample = Sample {
            kind: "sample",
            index: samples.len(),
            elapsed_s: elapsed.as_secs_f64(),
            unix_ms: unix_ms(),
            server_alive: server.alive(),
            rss,
            rss_unavailable,
            agents_live: agents.iter().filter(|task| !task.is_finished()).count(),
            spectators_live: spectators.iter().filter(|task| !task.is_finished()).count(),
            status,
            status_error,
        };
        write_line(&mut log, &sample)?;
        let alive = sample.server_alive;
        samples.push(sample);
        if last || !alive {
            break;
        }
        next += interval;
        let wake = next.min(measured + total);
        tokio::time::sleep_until(tokio::time::Instant::from_std(wake)).await;
    }
    let _ = stop_tx.send(true);
    let mut client_errors = Vec::new();
    for agent in agents {
        match tokio::time::timeout(Duration::from_secs(5), agent).await {
            Ok(Ok(Ok(()))) => {}
            Ok(Ok(Err(error))) => client_errors.push(format!("agent: {error}")),
            Ok(Err(error)) => client_errors.push(format!("agent task: {error}")),
            Err(_) => client_errors.push("agent did not stop".to_string()),
        }
    }
    for spectator in spectators {
        match tokio::time::timeout(Duration::from_secs(5), spectator).await {
            Ok(Ok(Ok(outcome))) if outcome.disconnected => {
                client_errors.push(format!(
                    "spectator dropped after {} snapshots",
                    outcome.snapshots
                ));
            }
            Ok(Ok(Ok(_))) => {}
            Ok(Ok(Err(error))) => client_errors.push(format!("spectator: {error}")),
            Ok(Err(error)) => client_errors.push(format!("spectator task: {error}")),
            Err(_) => client_errors.push("spectator did not stop".to_string()),
        }
    }
    let exit = server.stop().await;
    let mut verdict = check_soak(
        &samples,
        Expected {
            agents: config.agents,
            spectators: config.spectators,
        },
    );
    verdict.problems.extend(client_errors);
    if exit != "stopped by the harness" {
        verdict.problems.push(format!("server {exit}"));
    }
    verdict.notes.push(format!(
        "wall time {:.0} s; server log {}",
        started.elapsed().as_secs_f64(),
        server_log.display()
    ));
    verdict.passed = verdict.problems.is_empty();
    write_line(&mut log, &verdict)?;
    Ok(verdict)
}

/// The sibling `fragr-server` next to this executable, as cargo lays out a
/// workspace's `target/<profile>/` directory.
pub fn default_server_binary() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let name = format!("fragr-server{}", std::env::consts::EXE_SUFFIX);
    let candidate = exe.parent()?.join(name);
    candidate.is_file().then_some(candidate)
}

#[cfg(test)]
mod tests;
