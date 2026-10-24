//! Repeatable local spectator delivery measurements over the real WebSocket path.

use super::{agent_task, transport, Error, Policy, TICKS_PER_SECOND};
use fragr_server::protocol::{ClientMessage, Role, ServerMessage};
use fragr_server::run::{run_server_with_metrics, RunMetrics, ServerOptions};
use fragr_server::sim::{MapKind, MatchConfig};
use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use std::collections::BTreeMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::net::{TcpSocket, TcpStream};
use tokio::sync::{oneshot, watch};
use tokio_tungstenite::{client_async, tungstenite::Message, WebSocketStream};

/// The current per-IP connection cap allows the largest row exactly.
pub const MAX_LOCAL_ROSTER: usize = 32;

#[derive(Debug, Clone, Serialize)]
pub struct Distribution {
    pub samples: usize,
    pub p50: f64,
    pub p99: f64,
    pub max: f64,
}

impl Distribution {
    fn from_values(values: &[f64]) -> Self {
        let mut sorted = values.to_vec();
        sorted.sort_by(f64::total_cmp);
        let pick = |fraction: f64| {
            sorted
                .get(((sorted.len().saturating_sub(1)) as f64 * fraction).round() as usize)
                .copied()
                .unwrap_or_default()
        };
        Self {
            samples: sorted.len(),
            p50: pick(0.5),
            p99: pick(0.99),
            max: sorted.last().copied().unwrap_or_default(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct FanoutRow {
    pub map: String,
    pub map_id: u32,
    pub seed: u64,
    pub fighters: usize,
    pub spectators: usize,
    pub measured_seconds: f64,
    pub watcher_snapshots: usize,
    pub watcher_text_bytes: usize,
    pub watcher_text_bytes_per_second: f64,
    pub missing_snapshot_ticks: u64,
    pub watcher_disconnects: usize,
    /// Relative arrival time against the earliest watcher for each tick.
    pub relative_snapshot_age_ms: Distribution,
    pub snapshot_interval_ms: Distribution,
    /// From the start of the server tick that built a Snapshot to a watcher
    /// reading its text frame, before the watcher parses it. One process and
    /// one clock, over loopback.
    pub tick_to_watcher_ms: Distribution,
    /// JSON encoding time per measured second: the tick task's broadcast
    /// encode plus every session writer's own serialization.
    pub serialization_ms_per_second: f64,
    /// Server timing, outbound queue and session writer samples from the run loop.
    pub server_metrics: serde_json::Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct FanoutReport {
    pub schema: u32,
    pub build: fragr_server::protocol::BuildInfo,
    pub environment: fragr_server::bench::BenchEnvironment,
    pub seconds_per_row: u64,
    pub rows: Vec<FanoutRow>,
}

/// Total milliseconds a summary's samples represent.
fn total_ms(summary: &fragr_server::bench::Summary) -> f64 {
    summary.mean * summary.count as f64
}

fn serialization_ms_per_second(report: &fragr_server::run::RunMetricsReport, seconds: f64) -> f64 {
    if seconds <= 0.0 {
        return 0.0;
    }
    (total_ms(&report.broadcast_encode_ms) + total_ms(&report.writer.encode_ms)) / seconds
}

#[derive(Debug, Clone)]
struct Arrival {
    tick: u64,
    at: Instant,
}

#[derive(Debug, Default)]
struct WatchResult {
    arrivals: Vec<Arrival>,
    text_bytes: usize,
    disconnected: bool,
}

fn read_message(
    message: Option<Result<Message, tokio_tungstenite::tungstenite::Error>>,
    stopping: bool,
    result: &mut WatchResult,
) -> Option<Message> {
    match message {
        Some(Ok(message)) => Some(message),
        Some(Err(_)) | None => {
            result.disconnected = !stopping;
            None
        }
    }
}

fn require_live_watchers(results: &[WatchResult]) -> Result<(), Error> {
    if results.is_empty() || results.iter().any(|watcher| watcher.arrivals.is_empty()) {
        return Err(Error::Server("fanout watcher received no snapshots".into()));
    }
    Ok(())
}

/// The server admits eight loopback spectators per address, so each eight
/// watchers take the next 127/8 source address.
const WATCHERS_PER_ADDRESS: usize = 8;

fn watcher_source(index: usize) -> Result<std::net::Ipv4Addr, Error> {
    let host = u8::try_from(1 + index / WATCHERS_PER_ADDRESS)
        .map_err(|_| Error::Server("too many fanout watchers".into()))?;
    Ok(std::net::Ipv4Addr::new(127, 0, 0, host))
}

/// Connect from a chosen loopback source. Linux routes all of 127/8 to the
/// loopback device; a platform that does not refuses the bind here.
async fn connect_from(
    url: &str,
    server: SocketAddr,
    source: std::net::Ipv4Addr,
) -> Result<WebSocketStream<TcpStream>, Error> {
    let socket = TcpSocket::new_v4().map_err(transport)?;
    socket
        .bind(SocketAddr::from((source, 0)))
        .map_err(|error| Error::Server(format!("fanout watcher cannot bind {source}: {error}")))?;
    let stream = socket.connect(server).await.map_err(transport)?;
    let (socket, _) = client_async(url, stream).await.map_err(transport)?;
    Ok(socket)
}

async fn watcher_task(
    url: String,
    server: SocketAddr,
    source: std::net::Ipv4Addr,
    name: String,
    ready: oneshot::Sender<()>,
    mut start: watch::Receiver<Option<Instant>>,
    mut stop: watch::Receiver<bool>,
) -> Result<WatchResult, Error> {
    let socket = connect_from(&url, server, source).await?;
    let (mut sink, mut stream) = socket.split();
    sink.send(Message::Text(
        serde_json::to_string(&ClientMessage::Hello {
            body: None,
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
    let (mut welcomed, mut mapped) = (false, false);
    let mut ready = Some(ready);
    let mut result = WatchResult::default();
    loop {
        let message = tokio::select! {
            _ = stop.changed() => break,
            changed = start.changed(), if start.borrow().is_none() => {
                if changed.is_err() { break; }
                continue;
            }
            message = stream.next() => message,
        };
        let Some(message) = read_message(message, *stop.borrow(), &mut result) else {
            break;
        };
        let Message::Text(text) = message else {
            if matches!(message, Message::Close(_)) {
                result.disconnected = !*stop.borrow();
                break;
            }
            continue;
        };
        // Arrival is the frame read, not the end of this watcher's parse.
        let read_at = Instant::now();
        if start.borrow().is_some() {
            result.text_bytes += text.len();
        }
        match serde_json::from_str::<ServerMessage>(&text).map_err(transport)? {
            ServerMessage::Welcome { role, .. } => {
                if role != Role::Spectator {
                    return Err(Error::Server("watcher received wrong role".into()));
                }
                welcomed = true;
            }
            ServerMessage::MapInfo { .. } => mapped = true,
            ServerMessage::Snapshot(snapshot) => {
                if start.borrow().is_some() {
                    result.arrivals.push(Arrival {
                        tick: snapshot.tick,
                        at: read_at,
                    });
                }
            }
            ServerMessage::Error { code, message } => {
                return Err(Error::Server(format!("watcher {code}: {message}")));
            }
            _ => {}
        }
        if welcomed && mapped {
            if let Some(sender) = ready.take() {
                let _ = sender.send(());
            }
        }
    }
    let _ = sink.close().await;
    Ok(result)
}

/// What the in-process server measured over the same window.
#[derive(Debug, Default)]
struct ServerSide {
    metrics: serde_json::Value,
    serialization_ms_per_second: f64,
    tick_starts: BTreeMap<u64, Instant>,
}

fn measure_arrivals(
    map: MapKind,
    fighters: usize,
    spectators: usize,
    seed: u64,
    seconds: f64,
    watcher_results: Vec<WatchResult>,
    server: ServerSide,
) -> FanoutRow {
    let mut earliest = BTreeMap::<u64, Instant>::new();
    for watcher in &watcher_results {
        for arrival in &watcher.arrivals {
            earliest
                .entry(arrival.tick)
                .and_modify(|at| *at = (*at).min(arrival.at))
                .or_insert(arrival.at);
        }
    }
    let mut ages = Vec::new();
    let mut tick_ages = Vec::new();
    let mut intervals = Vec::new();
    let mut missing_ticks = 0;
    let mut text_bytes = 0;
    let mut snapshots = 0;
    let mut disconnects = 0;
    for watcher in watcher_results {
        disconnects += usize::from(watcher.disconnected);
        text_bytes += watcher.text_bytes;
        let mut previous: Option<Arrival> = None;
        for arrival in watcher.arrivals {
            snapshots += 1;
            if let Some(first) = earliest.get(&arrival.tick) {
                ages.push(arrival.at.duration_since(*first).as_secs_f64() * 1000.0);
            }
            if let Some(started) = server.tick_starts.get(&arrival.tick) {
                tick_ages.push(arrival.at.duration_since(*started).as_secs_f64() * 1000.0);
            }
            if let Some(prior) = previous {
                missing_ticks += arrival.tick.saturating_sub(prior.tick + 1);
                intervals.push(arrival.at.duration_since(prior.at).as_secs_f64() * 1000.0);
            }
            previous = Some(arrival);
        }
    }
    FanoutRow {
        map: map.name().to_string(),
        map_id: map.id(),
        seed,
        fighters,
        spectators,
        measured_seconds: seconds,
        watcher_snapshots: snapshots,
        watcher_text_bytes: text_bytes,
        watcher_text_bytes_per_second: text_bytes as f64 / seconds,
        missing_snapshot_ticks: missing_ticks,
        watcher_disconnects: disconnects,
        relative_snapshot_age_ms: Distribution::from_values(&ages),
        snapshot_interval_ms: Distribution::from_values(&intervals),
        tick_to_watcher_ms: Distribution::from_values(&tick_ages),
        serialization_ms_per_second: server.serialization_ms_per_second,
        server_metrics: server.metrics,
    }
}

async fn one_row(
    map: MapKind,
    fighters: usize,
    spectators: usize,
    seed: u64,
    seconds: u64,
) -> Result<FanoutRow, Error> {
    if fighters == 0 || spectators == 0 || fighters + spectators > MAX_LOCAL_ROSTER {
        return Err(Error::Server("invalid local fanout roster".into()));
    }
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let (bound_tx, bound_rx) = oneshot::channel();
    let metrics = Arc::new(Mutex::new(RunMetrics::default()));
    let metrics_for_server = Arc::clone(&metrics);
    let server = tokio::spawn(async move {
        run_server_with_metrics(
            ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: 0,
                map,
                map_rotate: false,
                match_config: Some(MatchConfig {
                    frag_limit: None,
                    time_limit_ticks: Some(((seconds + 90) * TICKS_PER_SECOND as u64) as u32),
                    boss_spawn_ticks: None,
                    compliance_ping_ticks: None,
                    ..MatchConfig::default()
                }),
                seed,
                status_every_s: 0,
                ..ServerOptions::default()
            },
            async move {
                let _ = shutdown_rx.await;
            },
            Some(bound_tx),
            metrics_for_server,
        )
        .await
        .map_err(|error| error.to_string())
    });
    let addr = tokio::time::timeout(Duration::from_secs(30), bound_rx)
        .await
        .map_err(|_| Error::Timeout("fanout server bind"))?
        .map_err(|_| Error::Server("fanout server exited before bind".into()))?;
    let url = format!("ws://{addr}");
    let (stop_tx, stop_rx) = watch::channel(false);
    let (start_tx, start_rx) = watch::channel(None);
    let mut fighter_tasks = Vec::new();
    let mut fighter_ready = Vec::new();
    for index in 0..fighters {
        let (tx, rx) = oneshot::channel();
        fighter_ready.push(rx);
        fighter_tasks.push(tokio::spawn(agent_task(
            url.clone(),
            format!("Fighter-{}", index + 1),
            Policy::Reflex,
            stop_rx.clone(),
            Some(tx),
        )));
    }
    for ready in fighter_ready {
        tokio::time::timeout(Duration::from_secs(30), ready)
            .await
            .map_err(|_| Error::Timeout("fanout fighter ready"))?
            .map_err(|_| Error::Server("fanout fighter exited before ready".into()))?;
    }
    let mut watcher_tasks = Vec::new();
    let mut watcher_ready = Vec::new();
    for index in 0..spectators {
        let (tx, rx) = oneshot::channel();
        watcher_ready.push(rx);
        watcher_tasks.push(tokio::spawn(watcher_task(
            url.clone(),
            addr,
            watcher_source(index)?,
            format!("Watcher-{}", index + 1),
            tx,
            start_rx.clone(),
            stop_rx.clone(),
        )));
    }
    for ready in watcher_ready {
        tokio::time::timeout(Duration::from_secs(30), ready)
            .await
            .map_err(|_| Error::Timeout("fanout watcher ready"))?
            .map_err(|_| Error::Server("fanout watcher exited before ready".into()))?;
    }
    if fighter_tasks
        .iter()
        .any(tokio::task::JoinHandle::is_finished)
    {
        return Err(Error::Server(
            "fighter disconnected before fanout measurement".into(),
        ));
    }
    metrics
        .lock()
        .map_err(|_| Error::Server("fanout metrics lock poisoned".into()))?
        .reset();
    let started = Instant::now();
    let _ = start_tx.send(Some(started));
    tokio::time::sleep(Duration::from_secs(seconds)).await;
    let elapsed = started.elapsed().as_secs_f64();
    if fighter_tasks
        .iter()
        .any(tokio::task::JoinHandle::is_finished)
    {
        return Err(Error::Server(
            "fighter disconnected during fanout measurement".into(),
        ));
    }
    let server_side = {
        let metrics = metrics
            .lock()
            .map_err(|_| Error::Server("fanout metrics lock poisoned".into()))?;
        let report = metrics.report();
        ServerSide {
            serialization_ms_per_second: serialization_ms_per_second(&report, elapsed),
            metrics: serde_json::to_value(report).map_err(transport)?,
            tick_starts: metrics.tick_starts().collect(),
        }
    };
    let _ = stop_tx.send(true);
    let mut watcher_results = Vec::new();
    for task in watcher_tasks {
        watcher_results.push(
            tokio::time::timeout(Duration::from_secs(5), task)
                .await
                .map_err(|_| Error::Timeout("fanout watcher stop"))?
                .map_err(|error| Error::Server(error.to_string()))??,
        );
    }
    require_live_watchers(&watcher_results)?;
    let _ = shutdown_tx.send(());
    tokio::time::timeout(Duration::from_secs(5), server)
        .await
        .map_err(|_| Error::Timeout("fanout server stop"))?
        .map_err(|error| Error::Server(error.to_string()))?
        .map_err(Error::Server)?;
    for task in fighter_tasks {
        tokio::time::timeout(Duration::from_secs(5), task)
            .await
            .map_err(|_| Error::Timeout("fanout fighter stop"))?
            .map_err(|error| Error::Server(error.to_string()))??;
    }
    Ok(measure_arrivals(
        map,
        fighters,
        spectators,
        seed,
        elapsed,
        watcher_results,
        server_side,
    ))
}

/// Measure 4 and 16 active fighters against 1, 8, and 16 watchers on both
/// smallest and largest multiplayer maps. Every row starts a fresh seeded match.
pub async fn matrix(seconds_per_row: u64) -> Result<FanoutReport, Error> {
    if !(2..=120).contains(&seconds_per_row) {
        return Err(Error::Server("fanout seconds must be 2 through 120".into()));
    }
    let mut rows = Vec::new();
    for map in [MapKind::ArenaDuel, MapKind::TripointWorks] {
        for fighters in [4, 16] {
            for spectators in [1, 8, 16] {
                rows.push(one_row(map, fighters, spectators, 42, seconds_per_row).await?);
            }
        }
    }
    Ok(FanoutReport {
        schema: 2,
        build: fragr_server::metrics::build_info(),
        environment: fragr_server::bench::BenchEnvironment::current(),
        seconds_per_row,
        rows,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distribution_handles_small_samples() {
        assert_eq!(Distribution::from_values(&[]).samples, 0);
        let values = Distribution::from_values(&[7.0, 1.0, 3.0]);
        assert_eq!(values.samples, 3);
        assert_eq!(values.p50, 3.0);
        assert_eq!(values.p99, 7.0);
    }

    #[test]
    fn age_and_gap_are_measured_per_watcher() {
        let at = Instant::now();
        let row = measure_arrivals(
            MapKind::ArenaDuel,
            4,
            2,
            42,
            1.0,
            vec![
                WatchResult {
                    arrivals: vec![
                        Arrival { tick: 10, at },
                        Arrival {
                            tick: 12,
                            at: at + Duration::from_millis(100),
                        },
                    ],
                    text_bytes: 240,
                    disconnected: false,
                },
                WatchResult {
                    arrivals: vec![Arrival {
                        tick: 10,
                        at: at + Duration::from_millis(5),
                    }],
                    text_bytes: 80,
                    disconnected: true,
                },
            ],
            ServerSide {
                serialization_ms_per_second: 1.5,
                // Tick 12 has no recorded start, so only tick 10 is timed.
                tick_starts: BTreeMap::from([(10, at)]),
                ..ServerSide::default()
            },
        );
        assert_eq!(row.watcher_snapshots, 3);
        assert_eq!(row.watcher_text_bytes, 320);
        assert_eq!(row.missing_snapshot_ticks, 1);
        assert_eq!(row.watcher_disconnects, 1);
        assert_eq!(row.relative_snapshot_age_ms.max, 5.0);
        assert_eq!(row.tick_to_watcher_ms.samples, 2);
        assert_eq!(row.tick_to_watcher_ms.max, 5.0);
        let json = serde_json::to_value(FanoutReport {
            schema: 2,
            build: fragr_server::metrics::build_info(),
            environment: fragr_server::bench::BenchEnvironment::current(),
            seconds_per_row: 10,
            rows: vec![row],
        })
        .unwrap();
        assert_eq!(json["schema"], 2);
        assert_eq!(json["rows"][0]["missing_snapshot_ticks"], 1);
        assert_eq!(json["rows"][0]["relative_snapshot_age_ms"]["samples"], 3);
        assert_eq!(json["rows"][0]["serialization_ms_per_second"], 1.5);
        assert!(json["environment"]["available_parallelism"].is_number());
    }

    #[test]
    fn every_eight_watchers_take_the_next_loopback_source() {
        assert_eq!(watcher_source(0).unwrap().octets(), [127, 0, 0, 1]);
        assert_eq!(watcher_source(7).unwrap().octets(), [127, 0, 0, 1]);
        assert_eq!(watcher_source(8).unwrap().octets(), [127, 0, 0, 2]);
        assert_eq!(watcher_source(15).unwrap().octets(), [127, 0, 0, 2]);
        assert!(watcher_source(usize::MAX).is_err());
    }

    #[test]
    fn serialization_rate_sums_tick_and_writer_encodes() {
        let probe = fragr_server::net::WriterProbe::default();
        let mut report = fragr_server::run::RunMetrics::default().report();
        assert_eq!(serialization_ms_per_second(&report, 2.0), 0.0);
        report.broadcast_encode_ms.mean = 0.5;
        report.broadcast_encode_ms.count = 40;
        report.writer = probe.report();
        report.writer.encode_ms.mean = 0.25;
        report.writer.encode_ms.count = 80;
        assert_eq!(serialization_ms_per_second(&report, 2.0), 20.0);
        assert_eq!(serialization_ms_per_second(&report, 0.0), 0.0);
    }

    #[test]
    fn read_failure_is_a_disconnect_and_empty_traces_fail() {
        let mut watcher = WatchResult::default();
        let message = read_message(
            Some(Err(tokio_tungstenite::tungstenite::Error::ConnectionClosed)),
            false,
            &mut watcher,
        );
        assert!(message.is_none());
        assert!(watcher.disconnected);
        assert!(require_live_watchers(&[watcher]).is_err());
    }
}
