//! Synthetic traffic against a local authoritative server.
//!
//! Fighters send plain movement and fire at a fixed rate. Spectators only
//! read. Nobody pathfinds. The server is the dedicated binary, or `run_server`
//! in this process for tests, and it is stopped through the handle this
//! harness owns.
//!
//! Against the binary, the report also carries what the server process paid:
//! its resident set before, during and after the roster, CPU time over the
//! held window, kernel socket memory, and its own tick trace for that window.

pub mod host;

use super::{soak, transport, Error};
use fragr_server::protocol::{Action, ClientMessage, Role, ServerMessage};
use fragr_server::sim::MapKind;
use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::net::TcpStream;
use tokio::sync::watch;
use tokio_tungstenite::{client_async, tungstenite::Message, WebSocketStream};

/// Report schema. Bump it when a field changes meaning. 2 added the server
/// process costs, the tick window, bursts and idle fighters.
pub const TRAFFIC_SCHEMA: u32 = 2;
/// Rule bots the generator may ask for, beside the socket roster.
pub const MAX_BOTS: usize = 96;
/// Fighters per source address: under the loopback join rate (30 joins per
/// address in ten seconds) and the 32-connection address cap.
pub const FIGHTERS_PER_ADDRESS: usize = 24;
/// Spectators per source address: the loopback spectator cap.
pub const SPECTATORS_PER_ADDRESS: usize = 8;
/// WebSocket clients one server process may hold.
pub const MAX_CLIENTS: usize = 64;
/// Stay under the server's 256 inbound messages per second.
pub const MAX_HZ: u32 = 120;

#[derive(Debug, Clone)]
pub struct TrafficConfig {
    pub seconds: u64,
    pub fighters: usize,
    pub spectators: usize,
    pub bots: usize,
    /// Actions per fighter per second. Zero holds fighters idle: joined and
    /// reading, sending nothing.
    pub hz: u32,
    /// Actions written back to back per send; the mean rate stays `hz`.
    pub burst: u32,
    pub map: MapKind,
    pub seed: u64,
    pub launch: soak::Launch,
    pub report: PathBuf,
}

impl TrafficConfig {
    pub fn validate(&self) -> Result<(), Error> {
        if self.seconds == 0 || self.seconds > 3600 {
            return Err(Error::Server(
                "traffic seconds must be 1 through 3600".into(),
            ));
        }
        if self.hz > MAX_HZ {
            return Err(Error::Server(format!(
                "traffic rate must be 0 through {MAX_HZ} actions per second"
            )));
        }
        if self.burst == 0 || self.burst > 64 || (self.hz > 0 && self.burst > self.hz) {
            return Err(Error::Server(
                "a burst is 1 through 64 actions and no more than one second of input".into(),
            ));
        }
        let clients = self.fighters + self.spectators;
        if clients == 0 || clients > MAX_CLIENTS {
            return Err(Error::Server(format!(
                "fighters plus spectators must be 1 through {MAX_CLIENTS}"
            )));
        }
        if self.bots > MAX_BOTS {
            return Err(Error::Server(format!(
                "traffic bots must be 0 through {MAX_BOTS}"
            )));
        }
        Ok(())
    }

    /// How often a fighter writes, and how many actions each time.
    fn cadence(&self) -> Option<(Duration, u32)> {
        (self.hz > 0).then(|| {
            (
                Duration::from_secs_f64(f64::from(self.burst) / f64::from(self.hz)),
                self.burst,
            )
        })
    }
}

/// The server process's resident set at each phase of the run, in bytes.
#[derive(Debug, Clone, Default, Serialize)]
pub struct PhaseMemory {
    /// After the status line answers, before any client connects.
    pub before_clients: Option<u64>,
    /// Every client has its first snapshot.
    pub connected: Option<u64>,
    /// End of the held window.
    pub end: Option<u64>,
    /// Two seconds after every client closed.
    pub after_leave: Option<u64>,
    pub source: Option<&'static str>,
}

/// What the server process paid over the held window.
#[derive(Debug, Clone, Default, Serialize)]
pub struct ServerCost {
    pub rss_bytes: PhaseMemory,
    /// CPU time over the held window, all threads, in milliseconds.
    pub cpu_ms: Option<f64>,
    /// `cpu_ms` per wall second, as a share of one core.
    pub cpu_cores: Option<f64>,
    /// Kernel memory of its established sockets at the end of the window.
    pub sockets: Option<host::SocketMemory>,
    pub ticks: Option<host::TickWindow>,
    /// Why a cost above is absent.
    pub unavailable: Vec<String>,
}

/// Last octet of `127.0.0.x` for a seat. Each address from .1 holds up to 24
/// fighters and 8 spectators, 32 connections, so no address meets a server
/// bound and a small roster stays on .1 (all macOS assigns by default).
fn source_octet(seat: &Seat) -> u8 {
    let octet = match seat {
        Seat::Fighter { index } => 1 + index / FIGHTERS_PER_ADDRESS,
        Seat::Spectator { index } => 1 + index / SPECTATORS_PER_ADDRESS,
    };
    u8::try_from(octet).unwrap_or(u8::MAX)
}

#[derive(Debug, Clone, Serialize)]
pub struct TrafficReport {
    pub schema: u32,
    pub seconds: u64,
    pub fighters: usize,
    pub spectators: usize,
    pub bots: usize,
    pub hz: u32,
    pub burst: u32,
    pub seed: u64,
    pub map: String,
    pub build: fragr_server::protocol::BuildInfo,
    pub environment: fragr_server::bench::BenchEnvironment,
    pub connected_fighters: usize,
    pub connected_spectators: usize,
    pub actions_sent: u64,
    pub fighter_snapshots: u64,
    pub spectator_snapshots: u64,
    pub text_bytes: u64,
    pub disconnects: usize,
    pub tick_start: u64,
    pub tick_end: u64,
    pub humans_end: usize,
    pub connections_end: usize,
    pub health: Option<String>,
    pub tick_p99_ms: Option<f64>,
    pub out_bytes_per_s: Option<f64>,
    pub queue_overflows_total: Option<u64>,
    pub server: ServerCost,
    /// Snapshot composition as the first spectator (or fighter) read it.
    pub snapshot: host::SnapshotShape,
    pub server_exit: String,
    pub passed: bool,
    pub problems: Vec<String>,
}

#[derive(Debug, Default)]
struct SeatResult {
    welcomed: bool,
    actions_sent: u64,
    snapshots: u64,
    text_bytes: u64,
    disconnected: bool,
    shape: Option<host::SnapshotShape>,
}

enum Seat {
    Fighter { index: usize },
    Spectator { index: usize },
}

pub(crate) fn action(index: usize, step: u32) -> ClientMessage {
    let phase = step / 20;
    ClientMessage::Action(Action {
        forward: phase.is_multiple_of(2),
        back: phase % 2 == 1,
        left: index.is_multiple_of(2) && phase % 4 == 1,
        right: index % 2 == 1 && phase % 4 == 3,
        fire: true,
        yaw: Some((index as f32) * 0.7 + (step as f32) * 0.08),
        pitch: Some(0.0),
        seq: Some(step),
        ..Action::default()
    })
}

async fn open_socket(server: SocketAddr, octet: u8) -> Result<TcpStream, Error> {
    let socket = tokio::net::TcpSocket::new_v4()?;
    let local = SocketAddr::from(([127, 0, 0, octet], 0));
    socket.bind(local).map_err(|error| {
        if error.kind() == std::io::ErrorKind::AddrNotAvailable && octet != 1 {
            Error::Server(format!(
                "cannot bind a client to {local}: {error}. This machine has not assigned that loopback address. macOS needs an alias such as `ifconfig lo0 alias 127.0.0.{octet}` before a roster past 24 fighters or 8 spectators"
            ))
        } else {
            Error::Server(format!("cannot bind a client to {local}: {error}"))
        }
    })?;
    socket
        .connect(server)
        .await
        .map_err(|error| Error::Transport(format!("connect from {local}: {error}")))
}

/// One seat's socket roster role and pacing.
struct SeatPlan {
    seat: Seat,
    /// Fighters write `per_send` actions every period; `None` sends nothing.
    cadence: Option<(Duration, u32)>,
    /// Sample snapshot composition about once a second.
    shape: bool,
}

/// One snapshot in twenty, about one a second, is parsed for its shape.
const SHAPE_EVERY: u64 = 20;

async fn seat_task(
    server: SocketAddr,
    octet: u8,
    plan: SeatPlan,
    ready: tokio::sync::oneshot::Sender<()>,
    mut stop: watch::Receiver<bool>,
) -> Result<SeatResult, Error> {
    let stream = open_socket(server, octet).await?;
    let url = format!("ws://{server}/");
    let socket: WebSocketStream<TcpStream> = client_async(&url, stream).await.map_err(transport)?.0;
    let (mut sink, mut stream) = socket.split();
    let (role, name, index) = match plan.seat {
        Seat::Fighter { index } => (Role::Human, format!("Fighter {}", index + 1), Some(index)),
        Seat::Spectator { index } => (Role::Spectator, format!("Watcher {}", index + 1), None),
    };
    let hello = ClientMessage::Hello {
        body: None,
        seat: None,
        gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
        geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
        role,
        name,
        ticket: fragr_server::join_ticket::ticket_for(role),
        resume: None,
    };
    sink.send(Message::Text(
        serde_json::to_string(&hello).map_err(transport)?,
    ))
    .await
    .map_err(transport)?;
    let mut ready = Some(ready);
    let mut result = SeatResult {
        shape: plan.shape.then(host::SnapshotShape::default),
        ..SeatResult::default()
    };
    let mut step = 0u32;
    let mut world = fragr_server::protocol::WorldReader::new();
    let (period, per_send) = plan.cadence.unwrap_or((Duration::from_secs(3600), 0));
    let mut interval = tokio::time::interval(period);
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        let sending = result.welcomed && index.is_some() && per_send > 0;
        tokio::select! {
            _ = stop.changed() => break,
            _ = interval.tick(), if sending => {
                let Some(index) = index else {
                    continue;
                };
                // A burst goes out as one write, the way a stalled client
                // catches up.
                for _ in 0..per_send {
                    step = step.saturating_add(1);
                    let text = serde_json::to_string(&action(index, step)).map_err(transport)?;
                    if sink.feed(Message::Text(text)).await.is_err() {
                        result.disconnected = !*stop.borrow();
                        break;
                    }
                    result.actions_sent += 1;
                }
                if result.disconnected || sink.flush().await.is_err() {
                    result.disconnected = !*stop.borrow();
                    break;
                }
            }
            message = stream.next() => {
                let Some(message) = message else {
                    result.disconnected = !*stop.borrow();
                    break;
                };
                let Ok(Message::Text(text)) = message else {
                    if matches!(message, Ok(Message::Close(_)) | Err(_)) {
                        result.disconnected = !*stop.borrow();
                        break;
                    }
                    continue;
                };
                result.text_bytes += text.len() as u64;
                match world.read(&text) {
                    Ok(ServerMessage::Snapshot(snapshot)) => {
                        result.snapshots += 1;
                        if result.snapshots % SHAPE_EVERY == 1 {
                            if let Some(shape) = result.shape.as_mut() {
                                // The world as a full snapshot, whether it
                                // arrived whole or as a delta.
                                let full = serde_json::to_string(&ServerMessage::Snapshot(snapshot))
                                    .map_err(transport)?;
                                shape.observe(&full);
                            }
                        }
                        if !result.welcomed {
                            result.welcomed = true;
                            if let Some(ready) = ready.take() {
                                let _ = ready.send(());
                            }
                        }
                    }
                    Ok(ServerMessage::Error { code, message }) if !result.welcomed => {
                        return Err(Error::Server(format!("{code}: {message}")));
                    }
                    Err(fragr_server::protocol::delta::ReadError::Delta(error)) => {
                        return Err(Error::Server(error.to_string()));
                    }
                    _ => {}
                }
            }
        }
    }
    let _ = sink.close().await;
    Ok(result)
}

fn problems_for(config: &TrafficConfig, report: &TrafficReport) -> Vec<String> {
    let mut problems = Vec::new();
    if report.server_exit != "stopped by the harness" {
        problems.push(format!("server {}", report.server_exit));
    }
    if report.connected_fighters != config.fighters {
        problems.push(format!(
            "{} of {} fighters connected",
            report.connected_fighters, config.fighters
        ));
    }
    if report.connected_spectators != config.spectators {
        problems.push(format!(
            "{} of {} spectators connected",
            report.connected_spectators, config.spectators
        ));
    }
    if report.disconnects > 0 {
        problems.push(format!(
            "{} clients dropped during the run",
            report.disconnects
        ));
    }
    if report.tick_end <= report.tick_start {
        problems.push("the server tick did not advance".into());
    }
    if report.humans_end != config.fighters {
        problems.push(format!(
            "status ended with {} humans, asked for {}",
            report.humans_end, config.fighters
        ));
    }
    if report.connections_end != config.fighters + config.spectators {
        problems.push(format!(
            "status ended with {} connections, asked for {}",
            report.connections_end,
            config.fighters + config.spectators
        ));
    }
    let expected = config.fighters as u64 * u64::from(config.hz) * config.seconds;
    if config.fighters > 0 && report.actions_sent * 2 < expected {
        problems.push(format!(
            "sent {} actions, less than half of the {expected} a steady {} Hz would send",
            report.actions_sent, config.hz
        ));
    }
    if config.spectators > 0 && report.spectator_snapshots == 0 {
        problems.push("spectators received no snapshots".into());
    }
    problems
}

/// Run one traffic pass. The report is written to `config.report`.
pub async fn run(config: TrafficConfig) -> Result<TrafficReport, Error> {
    config.validate()?;
    if let Some(parent) = config
        .report
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
    {
        std::fs::create_dir_all(parent)?;
    }
    let server_log = server_log_path(&config.report);
    let tick_trace = sibling_path(&config.report, "ticks.ndjson");
    let (server, address) = soak::start_server(
        &soak::ServerSpec {
            bots: config.bots,
            map: config.map,
            map_rotate: false,
            seed: config.seed,
            launch: config.launch.clone(),
            tick_trace: Some(tick_trace.clone()),
        },
        &server_log,
    )
    .await?;
    let outcome = drive(server, address, &config, &tick_trace).await;
    let report = match outcome {
        Ok(report) => report,
        Err(error) => return Err(error),
    };
    let json = serde_json::to_string_pretty(&report).map_err(transport)?;
    std::fs::write(&config.report, format!("{json}\n"))?;
    Ok(report)
}

async fn finish_early(
    server: soak::Running,
    stop_tx: watch::Sender<bool>,
    tasks: Vec<tokio::task::JoinHandle<Result<SeatResult, Error>>>,
    error: Error,
) -> Error {
    let _ = stop_tx.send(true);
    // A refused seat says why; keep the first reason instead of a bare timeout.
    let mut cause = None;
    for task in tasks {
        if let Ok(Ok(Err(seat))) = tokio::time::timeout(Duration::from_secs(2), task).await {
            cause.get_or_insert(seat);
        }
    }
    let exit = server.stop().await;
    match cause {
        Some(seat) => Error::Server(format!("{error}: {seat} (server {exit})")),
        None => Error::Server(format!("{error} (server {exit})")),
    }
}

/// Samples of the server process, taken only when it is a child process:
/// an in-process server shares memory and CPU with its own clients.
struct ProcessProbe {
    pid: Option<u32>,
    cost: ServerCost,
}

impl ProcessProbe {
    fn new(server: &soak::Running, launch: &soak::Launch) -> Self {
        let mut cost = ServerCost::default();
        let pid = match launch {
            soak::Launch::Binary(_) => server.pid(),
            soak::Launch::InProcess => {
                cost.unavailable
                    .push("in-process server shares the harness process; no memory or CPU".into());
                None
            }
        };
        Self { pid, cost }
    }

    fn rss(&mut self) -> Option<u64> {
        let pid = self.pid?;
        match soak::sample_rss(pid) {
            Ok(rss) => {
                self.cost.rss_bytes.source = Some(rss.source);
                Some(rss.bytes)
            }
            Err(error) => {
                self.cost.unavailable.push(format!("resident set: {error}"));
                None
            }
        }
    }

    fn cpu(&mut self) -> Option<u64> {
        let pid = self.pid?;
        let cpu = host::cpu_ns(pid);
        if cpu.is_none() {
            self.cost
                .unavailable
                .push("CPU time is read from Linux schedstat".into());
        }
        cpu
    }
}

#[allow(clippy::too_many_lines)] // Connect, hold, sample, leave: one ordered run.
async fn drive(
    mut server: soak::Running,
    address: SocketAddr,
    config: &TrafficConfig,
    tick_trace: &Path,
) -> Result<TrafficReport, Error> {
    let mut probe = ProcessProbe::new(&server, &config.launch);
    probe.cost.rss_bytes.before_clients = probe.rss();
    let (stop_tx, stop_rx) = watch::channel(false);
    let mut tasks = Vec::new();
    let mut ready_wait = Vec::new();
    let seats = (0..config.fighters)
        .map(|index| SeatPlan {
            seat: Seat::Fighter { index },
            cadence: config.cadence(),
            shape: index == 0 && config.spectators == 0,
        })
        .chain((0..config.spectators).map(|index| SeatPlan {
            seat: Seat::Spectator { index },
            cadence: None,
            shape: index == 0,
        }));
    for plan in seats {
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        ready_wait.push(ready_rx);
        tasks.push(tokio::spawn(seat_task(
            address,
            source_octet(&plan.seat),
            plan,
            ready_tx,
            stop_rx.clone(),
        )));
    }
    for ready in ready_wait {
        match tokio::time::timeout(Duration::from_secs(15), ready).await {
            Ok(Ok(())) => {}
            Ok(Err(_)) | Err(_) => {
                return Err(finish_early(
                    server,
                    stop_tx,
                    tasks,
                    Error::Timeout("synthetic client welcome"),
                )
                .await);
            }
        }
    }
    probe.cost.rss_bytes.connected = probe.rss();
    let tick_start = soak::fetch_status(address, "/status").await?.tick;
    let held = std::time::Instant::now();
    let cpu_start = probe.cpu();
    tokio::time::sleep(Duration::from_secs(config.seconds)).await;
    let cpu_end = probe.cpu();
    let held_seconds = held.elapsed().as_secs_f64();
    if let (Some(start), Some(end)) = (cpu_start, cpu_end) {
        let ms = end.saturating_sub(start) as f64 / 1e6;
        probe.cost.cpu_ms = Some(ms);
        probe.cost.cpu_cores = Some(ms / 1000.0 / held_seconds);
    }
    if probe.pid.is_some() {
        match host::socket_memory(address.port()) {
            Ok(memory) => probe.cost.sockets = Some(memory),
            Err(error) => probe.cost.unavailable.push(error),
        }
    }
    probe.cost.rss_bytes.end = probe.rss();
    let end_status = if server.alive() {
        soak::fetch_status(address, "/status").await.ok()
    } else {
        None
    };
    let _ = stop_tx.send(true);
    let mut results = Vec::new();
    for task in tasks {
        match tokio::time::timeout(Duration::from_secs(10), task).await {
            Ok(Ok(Ok(result))) => results.push(result),
            Ok(Ok(Err(error))) => {
                let exit = server.stop().await;
                return Err(Error::Server(format!("{error} (server {exit})")));
            }
            Ok(Err(error)) => {
                let exit = server.stop().await;
                return Err(Error::Server(format!(
                    "client task failed: {error} (server {exit})"
                )));
            }
            Err(_) => {
                let exit = server.stop().await;
                return Err(Error::Server(format!(
                    "a client did not finish after the stop (server {exit})"
                )));
            }
        }
    }
    if probe.pid.is_some() {
        tokio::time::sleep(Duration::from_secs(2)).await;
        probe.cost.rss_bytes.after_leave = probe.rss();
    }
    let server_exit = server.stop().await;
    let tick_end = end_status
        .as_ref()
        .map(|status| status.tick)
        .unwrap_or(tick_start);
    match host::tick_window(tick_trace, tick_start, tick_end) {
        Ok(window) => probe.cost.ticks = Some(window),
        Err(error) => probe.cost.unavailable.push(format!("tick trace: {error}")),
    }
    let mut snapshot = results
        .iter_mut()
        .find_map(|result| result.shape.take())
        .unwrap_or_default();
    snapshot.finish();
    let connected_fighters = results
        .iter()
        .take(config.fighters)
        .filter(|r| r.welcomed)
        .count();
    let connected_spectators = results
        .iter()
        .skip(config.fighters)
        .filter(|r| r.welcomed)
        .count();
    let ops = end_status.as_ref().and_then(|status| status.ops.as_ref());
    let mut report = TrafficReport {
        schema: TRAFFIC_SCHEMA,
        seconds: config.seconds,
        fighters: config.fighters,
        spectators: config.spectators,
        bots: config.bots,
        hz: config.hz,
        burst: config.burst,
        seed: config.seed,
        map: config.map.name().to_string(),
        build: fragr_server::metrics::build_info(),
        environment: fragr_server::bench::BenchEnvironment::current(),
        connected_fighters,
        connected_spectators,
        actions_sent: results.iter().map(|result| result.actions_sent).sum(),
        fighter_snapshots: results
            .iter()
            .take(config.fighters)
            .map(|r| r.snapshots)
            .sum(),
        spectator_snapshots: results
            .iter()
            .skip(config.fighters)
            .map(|r| r.snapshots)
            .sum(),
        text_bytes: results.iter().map(|result| result.text_bytes).sum(),
        disconnects: results.iter().filter(|result| result.disconnected).count(),
        tick_start,
        tick_end,
        humans_end: end_status.as_ref().map(|status| status.humans).unwrap_or(0),
        connections_end: end_status
            .as_ref()
            .map(|status| status.connections)
            .unwrap_or(0),
        health: end_status.as_ref().and_then(|status| {
            status.health.as_ref().map(|health| match health.status {
                fragr_server::protocol::HealthState::Ok => "ok".to_string(),
                fragr_server::protocol::HealthState::Degraded => "degraded".to_string(),
            })
        }),
        tick_p99_ms: ops.map(|ops| ops.tick.lifetime.p99_ms),
        out_bytes_per_s: ops.map(|ops| ops.traffic.out_bytes_per_s),
        queue_overflows_total: ops.map(|ops| ops.traffic.queue_overflows_total),
        server: probe.cost,
        snapshot,
        server_exit,
        passed: false,
        problems: Vec::new(),
    };
    report.problems = problems_for(config, &report);
    report.passed = report.problems.is_empty();
    Ok(report)
}

/// `report.json` becomes `report.json.<suffix>` beside it.
fn sibling_path(report: &Path, suffix: &str) -> PathBuf {
    let mut name = report
        .file_name()
        .unwrap_or_else(|| std::ffi::OsStr::new("traffic"))
        .to_os_string();
    name.push(".");
    name.push(suffix);
    report.with_file_name(name)
}

fn server_log_path(report: &Path) -> PathBuf {
    let mut name = report
        .file_name()
        .unwrap_or_else(|| std::ffi::OsStr::new("traffic"))
        .to_os_string();
    name.push(".server.log");
    report.with_file_name(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addresses_stay_under_the_join_and_spectator_bounds() {
        let fighter = |index| source_octet(&Seat::Fighter { index });
        let watcher = |index| source_octet(&Seat::Spectator { index });
        assert_eq!(
            (fighter(0), fighter(23), fighter(24), fighter(47)),
            (1, 1, 2, 2)
        );
        assert_eq!(
            (watcher(0), watcher(7), watcher(8), watcher(15)),
            (1, 1, 2, 2)
        );
        assert_eq!(fighter(usize::MAX), u8::MAX);
        let ok = TrafficConfig {
            seconds: 2,
            fighters: 2,
            spectators: 1,
            bots: 0,
            hz: 20,
            burst: 1,
            map: MapKind::ArenaDuel,
            seed: 1,
            launch: soak::Launch::InProcess,
            report: PathBuf::from("traffic.json"),
        };
        ok.validate().unwrap();
        let mut too_many = ok.clone();
        too_many.fighters = 65;
        too_many.spectators = 0;
        assert!(too_many.validate().is_err());
        // Idle fighters join and read but never write.
        let mut idle = ok.clone();
        idle.hz = 0;
        idle.validate().unwrap();
        assert_eq!(idle.cadence(), None);
        assert_eq!(ok.cadence(), Some((Duration::from_millis(50), 1)));
        let mut burst = ok.clone();
        burst.hz = 60;
        burst.burst = 30;
        burst.validate().unwrap();
        assert_eq!(burst.cadence(), Some((Duration::from_millis(500), 30)));
        burst.burst = 61;
        assert!(burst.validate().is_err(), "more than a second of input");
        burst.burst = 0;
        assert!(burst.validate().is_err());
        let mut fast = ok.clone();
        fast.hz = MAX_HZ + 1;
        assert!(fast.validate().is_err());
        let mut crowd = ok.clone();
        crowd.bots = MAX_BOTS;
        crowd.validate().unwrap();
        crowd.bots = MAX_BOTS + 1;
        assert!(crowd.validate().is_err());
        assert_eq!(
            sibling_path(Path::new("dir/run.json"), "ticks.ndjson"),
            PathBuf::from("dir/run.json.ticks.ndjson")
        );
    }

    #[tokio::test]
    async fn a_second_loopback_address_connects() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let server = listener.local_addr().unwrap();
        let socket = tokio::net::TcpSocket::new_v4().unwrap();
        let local: SocketAddr = "127.0.0.2:0".parse().unwrap();
        match socket.bind(local) {
            Ok(()) => {
                let _stream = socket.connect(server).await.unwrap();
                let (accepted, _) = listener.accept().await.unwrap();
                assert_eq!(accepted.peer_addr().unwrap().ip(), local.ip());
            }
            Err(error) if error.kind() == std::io::ErrorKind::AddrNotAvailable => {
                // Linux and Windows assign 127.0.0.0/8. macOS assigns
                // 127.0.0.1 until an alias is added, so a roster past 32
                // is refused there until that address exists.
                #[cfg(not(target_os = "macos"))]
                panic!("127.0.0.2 must be bindable on this OS: {error}");
                #[cfg(target_os = "macos")]
                let _ = error;
            }
            Err(error) => panic!("bind {local}: {error}"),
        }
    }

    #[tokio::test]
    async fn a_short_local_roster_moves_and_watches() {
        let dir = std::env::temp_dir().join(format!("fragr-traffic-{}", std::process::id()));
        let report_path = dir.join("traffic.json");
        let report = run(TrafficConfig {
            seconds: 2,
            fighters: 2,
            spectators: 1,
            bots: 0,
            hz: 20,
            burst: 2,
            map: MapKind::ArenaDuel,
            seed: 3,
            launch: soak::Launch::InProcess,
            report: report_path.clone(),
        })
        .await
        .unwrap();
        assert!(report.passed, "{:?}", report.problems);
        assert!(report.actions_sent >= 40, "{}", report.actions_sent);
        assert!(report.fighter_snapshots > 0);
        assert!(report.spectator_snapshots > 0);
        assert!(report.text_bytes > 0);
        assert!(report.tick_end > report.tick_start);
        assert_eq!(report.humans_end, 2);
        assert_eq!(report.connections_end, 3);
        let saved: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&report_path).unwrap()).unwrap();
        assert_eq!(saved["schema"], 2);
        assert_eq!(saved["burst"], 2);
        // In process, the server's own trace still covers the held ticks, but
        // memory and CPU would mix with the clients and are not reported.
        let ticks = report.server.ticks.as_ref().expect("tick window");
        assert!(ticks.ticks > 0);
        assert!(report.server.rss_bytes.connected.is_none());
        assert!(report.server.cpu_ms.is_none());
        assert!(!report.server.unavailable.is_empty());
        assert!(report.snapshot.sampled > 0);
        assert!(report.snapshot.mean_bytes > 0.0);
        assert!(report.snapshot.mean_players >= 2.0);
        assert_eq!(saved["passed"], true);
        let _ = std::fs::remove_dir_all(dir);
    }
}
