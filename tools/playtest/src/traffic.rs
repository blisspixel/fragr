//! Synthetic traffic against a local authoritative server.
//!
//! Fighters send plain movement and fire at a fixed rate. Spectators only
//! read. Nobody pathfinds. The server is the dedicated binary, or `run_server`
//! in this process for tests, and it is stopped through the handle this
//! harness owns.

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

/// Report schema. Bump it when a field changes meaning.
pub const TRAFFIC_SCHEMA: u32 = 1;
/// WebSocket clients one source address may hold. Matches the server cap.
pub const PER_ADDRESS: usize = 32;
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
    pub hz: u32,
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
        if self.hz == 0 || self.hz > MAX_HZ {
            return Err(Error::Server(format!(
                "traffic rate must be 1 through {MAX_HZ} actions per second"
            )));
        }
        let clients = self.fighters + self.spectators;
        if clients == 0 || clients > MAX_CLIENTS {
            return Err(Error::Server(format!(
                "fighters plus spectators must be 1 through {MAX_CLIENTS}"
            )));
        }
        if self.bots > PER_ADDRESS {
            return Err(Error::Server(format!(
                "traffic bots must be 0 through {PER_ADDRESS}"
            )));
        }
        Ok(())
    }
}

/// Last octet of `127.0.0.x` for client `index`. Each address holds 32.
pub fn source_octet(index: usize) -> u8 {
    1 + (index / PER_ADDRESS) as u8
}

#[derive(Debug, Clone, Serialize)]
pub struct TrafficReport {
    pub schema: u32,
    pub seconds: u64,
    pub fighters: usize,
    pub spectators: usize,
    pub bots: usize,
    pub hz: u32,
    pub seed: u64,
    pub map: String,
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
}

enum Seat {
    Fighter { index: usize },
    Spectator { index: usize },
}

fn action(index: usize, step: u32) -> ClientMessage {
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
    socket
        .bind(local)
        .map_err(|error| Error::Server(format!("cannot bind a client to {local}: {error}")))?;
    socket
        .connect(server)
        .await
        .map_err(|error| Error::Transport(format!("connect from {local}: {error}")))
}

async fn seat_task(
    server: SocketAddr,
    octet: u8,
    seat: Seat,
    hz: u32,
    ready: tokio::sync::oneshot::Sender<()>,
    mut stop: watch::Receiver<bool>,
) -> Result<SeatResult, Error> {
    let stream = open_socket(server, octet).await?;
    let url = format!("ws://{server}/");
    let socket: WebSocketStream<TcpStream> = client_async(&url, stream).await.map_err(transport)?.0;
    let (mut sink, mut stream) = socket.split();
    let (role, name, index) = match seat {
        Seat::Fighter { index } => (Role::Human, format!("Fighter {}", index + 1), Some(index)),
        Seat::Spectator { index } => (Role::Spectator, format!("Watcher {}", index + 1), None),
    };
    let hello = ClientMessage::Hello {
        body: None,
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
    let mut result = SeatResult::default();
    let mut step = 0u32;
    let mut interval = tokio::time::interval(Duration::from_secs_f64(1.0 / f64::from(hz)));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        let sending = result.welcomed && index.is_some();
        tokio::select! {
            _ = stop.changed() => break,
            _ = interval.tick(), if sending => {
                let Some(index) = index else {
                    continue;
                };
                step = step.saturating_add(1);
                let text = serde_json::to_string(&action(index, step)).map_err(transport)?;
                if sink.send(Message::Text(text)).await.is_err() {
                    result.disconnected = !*stop.borrow();
                    break;
                }
                result.actions_sent += 1;
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
                match serde_json::from_str::<ServerMessage>(&text) {
                    Ok(ServerMessage::Snapshot(_)) => {
                        result.snapshots += 1;
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
    let (server, address) = soak::start_server(
        &soak::ServerSpec {
            bots: config.bots,
            map: config.map,
            map_rotate: false,
            seed: config.seed,
            launch: config.launch.clone(),
        },
        &server_log,
    )
    .await?;
    let outcome = drive(server, address, &config).await;
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
    for task in tasks {
        let _ = tokio::time::timeout(Duration::from_secs(2), task).await;
    }
    let exit = server.stop().await;
    Error::Server(format!("{error} (server {exit})"))
}

async fn drive(
    mut server: soak::Running,
    address: SocketAddr,
    config: &TrafficConfig,
) -> Result<TrafficReport, Error> {
    let tick_start = soak::fetch_status(address, "/status").await?.tick;
    let (stop_tx, stop_rx) = watch::channel(false);
    let mut tasks = Vec::new();
    let mut ready_wait = Vec::new();
    for index in 0..config.fighters {
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        ready_wait.push(ready_rx);
        let stop = stop_rx.clone();
        tasks.push(tokio::spawn(seat_task(
            address,
            source_octet(index),
            Seat::Fighter { index },
            config.hz,
            ready_tx,
            stop,
        )));
    }
    for index in 0..config.spectators {
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        ready_wait.push(ready_rx);
        let stop = stop_rx.clone();
        tasks.push(tokio::spawn(seat_task(
            address,
            source_octet(config.fighters + index),
            Seat::Spectator { index },
            config.hz,
            ready_tx,
            stop,
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
    tokio::time::sleep(Duration::from_secs(config.seconds)).await;
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
    let server_exit = server.stop().await;
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
    let mut report = TrafficReport {
        schema: TRAFFIC_SCHEMA,
        seconds: config.seconds,
        fighters: config.fighters,
        spectators: config.spectators,
        bots: config.bots,
        hz: config.hz,
        seed: config.seed,
        map: config.map.name().to_string(),
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
        tick_end: end_status
            .as_ref()
            .map(|status| status.tick)
            .unwrap_or(tick_start),
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
        tick_p99_ms: end_status
            .as_ref()
            .and_then(|status| status.ops.as_ref())
            .map(|ops| ops.tick.lifetime.p99_ms),
        out_bytes_per_s: end_status
            .as_ref()
            .and_then(|status| status.ops.as_ref())
            .map(|ops| ops.traffic.out_bytes_per_s),
        server_exit,
        passed: false,
        problems: Vec::new(),
    };
    report.problems = problems_for(config, &report);
    report.passed = report.problems.is_empty();
    Ok(report)
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
    fn addresses_roll_after_thirty_two_and_the_roster_is_bounded() {
        assert_eq!(source_octet(0), 1);
        assert_eq!(source_octet(31), 1);
        assert_eq!(source_octet(32), 2);
        assert_eq!(source_octet(63), 2);
        let ok = TrafficConfig {
            seconds: 2,
            fighters: 2,
            spectators: 1,
            bots: 0,
            hz: 20,
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
        let mut idle = ok.clone();
        idle.hz = 0;
        assert!(idle.validate().is_err());
    }

    #[tokio::test]
    async fn a_second_loopback_address_connects() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let server = listener.local_addr().unwrap();
        let socket = tokio::net::TcpSocket::new_v4().unwrap();
        socket.bind("127.0.0.2:0".parse().unwrap()).unwrap();
        let _stream = socket.connect(server).await.unwrap();
        let _accepted = listener.accept().await.unwrap();
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
        assert_eq!(saved["schema"], 1);
        assert_eq!(saved["passed"], true);
        let _ = std::fs::remove_dir_all(dir);
    }
}
