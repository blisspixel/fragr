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

/// Report schema. 3 added the stress scenarios and the tick schedule.
pub const FANOUT_SCHEMA: u32 = 3;

/// How a watcher reads its stream.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum WatcherKind {
    /// Reads every frame as it arrives.
    Healthy,
    /// Reads one frame, then waits this long before the next.
    Slow { pause_ms: u64 },
    /// Stops reading once the measured window opens.
    Stalled,
}

/// How an input probe spaces its numbered actions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum InputPattern {
    /// One action every `1/hz` seconds.
    Steady { hz: u32 },
    /// `size` actions written back to back every `every_ms`.
    Burst { size: u32, every_ms: u64 },
}

impl InputPattern {
    fn period(self) -> Duration {
        match self {
            Self::Steady { hz } => Duration::from_secs_f64(1.0 / f64::from(hz.max(1))),
            Self::Burst { every_ms, .. } => Duration::from_millis(every_ms.max(1)),
        }
    }

    fn per_period(self) -> u32 {
        match self {
            Self::Steady { .. } => 1,
            Self::Burst { size, .. } => size.max(1),
        }
    }
}

/// One measured row: reflex fighters and healthy watchers, plus optional
/// degraded watchers or input probes.
#[derive(Debug, Clone, PartialEq)]
pub struct RowSpec {
    pub scenario: &'static str,
    pub map: MapKind,
    pub fighters: usize,
    pub spectators: usize,
    pub degraded: Option<(WatcherKind, usize)>,
    pub probes: Option<(InputPattern, usize)>,
}

impl RowSpec {
    fn plain(map: MapKind, fighters: usize, spectators: usize) -> Self {
        Self {
            scenario: "baseline",
            map,
            fighters,
            spectators,
            degraded: None,
            probes: None,
        }
    }

    fn validate(&self) -> Result<(), Error> {
        let degraded = self.degraded.map_or(0, |(_, count)| count);
        let probes = self.probes.map_or(0, |(_, count)| count);
        let watchers = self.spectators + degraded;
        if self.fighters == 0
            || self.spectators == 0
            || self.fighters + watchers + probes > MAX_LOCAL_ROSTER
            || watchers > MAX_LOCAL_WATCHERS
            || self
                .degraded
                .is_some_and(|(kind, count)| kind == WatcherKind::Healthy || count == 0)
            || self.probes.is_some_and(|(_, count)| count == 0)
        {
            return Err(Error::Server("invalid local fanout roster".into()));
        }
        Ok(())
    }
}

/// The server admits sixteen spectators in all.
pub const MAX_LOCAL_WATCHERS: usize = 16;

/// What the degraded watchers of a stress row saw.
#[derive(Debug, Clone, Serialize)]
pub struct DegradedSummary {
    pub kind: WatcherKind,
    pub watchers: usize,
    /// Snapshots they read inside the window (a stalled watcher reads none).
    pub snapshots: usize,
    /// Ticks they never saw between two they did: replaced or dropped worlds.
    pub missing_snapshot_ticks: u64,
    /// Watchers the server closed before the harness stopped.
    pub closed_by_server: usize,
    /// Tick start to reading the frame: how stale their picture became.
    pub tick_to_watcher_ms: Distribution,
}

/// Input probes: numbered human actions and the Ack that covered each.
#[derive(Debug, Clone, Serialize)]
pub struct InputSummary {
    pub pattern: InputPattern,
    pub probes: usize,
    pub actions_sent: u64,
    pub actions_acked: u64,
    /// Sent while an Ack showed the fighter down, or before the first
    /// applied Ack, so not timed.
    pub actions_unapplied: u64,
    /// From writing an action to reading the first applied Ack whose sequence
    /// covers it: inbound queueing, the wait for the next tick, and the Ack's
    /// way back. A burst's later actions overwrite earlier ones in the same
    /// tick, so a covered action is acknowledged, not necessarily applied.
    pub input_to_ack_ms: Distribution,
    pub disconnects: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct FanoutRow {
    pub scenario: String,
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
    /// Degraded watchers, reported apart from the healthy ones above.
    pub degraded: Option<DegradedSummary>,
    pub input: Option<InputSummary>,
    /// Milliseconds into the window at which `GET /status` first showed each
    /// lost connection, polled every 100 ms (so up to one poll late).
    pub connection_losses_ms: Vec<f64>,
    /// Server-side socket memory at the end of the window (Linux `ss`).
    pub sockets: Option<super::traffic::host::SocketMemory>,
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

/// After the window, read what a stalled watcher left in its socket until the
/// server's close shows, or the bounded drain ends with the socket still open.
async fn drain_closed<S>(stream: &mut S) -> bool
where
    S: futures_util::Stream<Item = Result<Message, tokio_tungstenite::tungstenite::Error>> + Unpin,
{
    let drain = async {
        loop {
            match stream.next().await {
                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => return true,
                Some(Ok(_)) => {}
            }
        }
    };
    tokio::time::timeout(Duration::from_secs(3), drain)
        .await
        .unwrap_or(false)
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

#[allow(clippy::too_many_arguments)] // One watcher: where, who, how, and its three signals.
async fn watcher_task(
    url: String,
    server: SocketAddr,
    source: std::net::Ipv4Addr,
    name: String,
    kind: WatcherKind,
    ready: oneshot::Sender<()>,
    mut start: watch::Receiver<Option<Instant>>,
    mut stop: watch::Receiver<bool>,
) -> Result<WatchResult, Error> {
    let socket = connect_from(&url, server, source).await?;
    let (mut sink, mut stream) = socket.split();
    sink.send(Message::Text(
        serde_json::to_string(&ClientMessage::Hello {
            body: None,
            seat: None,
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
    let mut world = fragr_server::protocol::WorldReader::new();
    loop {
        if kind == WatcherKind::Stalled && start.borrow().is_some() {
            // Read nothing for the window, then see whether the server closed.
            let _ = stop.changed().await;
            result.disconnected = drain_closed(&mut stream).await;
            break;
        }
        let message = tokio::select! {
            _ = stop.changed() => break,
            changed = start.changed(), if start.borrow().is_none() => {
                if changed.is_err() { break; }
                continue;
            }
            message = stream.next() => message,
        };
        let measuring = start.borrow().is_some();
        if let (WatcherKind::Slow { pause_ms }, true) = (kind, measuring) {
            tokio::select! {
                _ = stop.changed() => break,
                () = tokio::time::sleep(Duration::from_millis(pause_ms)) => {}
            }
        }
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
        match world.read(&text).map_err(transport)? {
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

#[derive(Debug, Default)]
struct ProbeResult {
    sent: u64,
    acked_ms: Vec<f64>,
    /// Actions dropped untimed: sent while an Ack showed the fighter down,
    /// or before the server applied its first input.
    unapplied: u64,
    disconnected: bool,
}

/// Every pending action the Ack's sequence covers gets one latency sample.
fn settle_acks(
    pending: &mut std::collections::VecDeque<(u32, Instant)>,
    seq: u32,
    at: Instant,
) -> Vec<f64> {
    let mut settled = Vec::new();
    while pending.front().is_some_and(|(sent, _)| *sent <= seq) {
        if let Some((_, sent_at)) = pending.pop_front() {
            settled.push(at.saturating_duration_since(sent_at).as_secs_f64() * 1000.0);
        }
    }
    settled
}

/// A human fighter that sends numbered actions in a fixed pattern once the
/// window opens and times each one to the Ack that covers it.
async fn probe_task(
    url: String,
    index: usize,
    pattern: InputPattern,
    ready: oneshot::Sender<()>,
    mut start: watch::Receiver<Option<Instant>>,
    mut stop: watch::Receiver<bool>,
) -> Result<ProbeResult, Error> {
    let (socket, _) = tokio_tungstenite::connect_async(&url)
        .await
        .map_err(transport)?;
    let (mut sink, mut stream) = socket.split();
    sink.send(Message::Text(
        serde_json::to_string(&ClientMessage::Hello {
            body: None,
            seat: None,
            gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
            geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
            role: Role::Human,
            name: format!("Probe-{}", index + 1),
            ticket: fragr_server::join_ticket::ticket_for(Role::Human),
            resume: None,
        })
        .map_err(transport)?,
    ))
    .await
    .map_err(transport)?;
    let mut ready = Some(ready);
    let mut result = ProbeResult::default();
    let mut world = fragr_server::protocol::WorldReader::new();
    let mut pending = std::collections::VecDeque::new();
    let mut acknowledged = false;
    let mut step = 0u32;
    let mut interval = tokio::time::interval(pattern.period());
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        let sending = start.borrow().is_some();
        tokio::select! {
            _ = stop.changed() => break,
            changed = start.changed(), if !sending => {
                if changed.is_err() { break; }
                interval.reset();
            }
            _ = interval.tick(), if sending => {
                for _ in 0..pattern.per_period() {
                    step = step.saturating_add(1);
                    let text = serde_json::to_string(&super::traffic::action(index, step))
                        .map_err(transport)?;
                    if sink.feed(Message::Text(text)).await.is_err() {
                        result.disconnected = !*stop.borrow();
                        break;
                    }
                    pending.push_back((step, Instant::now()));
                    result.sent += 1;
                }
                if result.disconnected || sink.flush().await.is_err() {
                    result.disconnected = !*stop.borrow();
                    break;
                }
            }
            message = stream.next() => {
                let Some(Ok(message)) = message else {
                    result.disconnected = !*stop.borrow();
                    break;
                };
                let Message::Text(text) = message else { continue };
                let at = Instant::now();
                match world.read(&text).map_err(transport)? {
                    ServerMessage::Ack { seq, movement, respawn_ticks, .. } => {
                        let applied = respawn_ticks.is_none()
                            && movement.as_ref().is_none_or(|movement| movement.applied);
                        if applied && acknowledged {
                            result.acked_ms.extend(settle_acks(&mut pending, seq, at));
                        } else if applied {
                            // The server Acks only once it has applied this
                            // fighter's first input; a fighter that opened the
                            // window down waits out its respawn first. Time
                            // only what follows the first applied Ack.
                            acknowledged = true;
                            result.unapplied += pending.len() as u64;
                            pending.clear();
                        } else {
                            // A downed or frozen fighter's input is never
                            // applied, so it is not timed.
                            result.unapplied += pending.len() as u64;
                            pending.clear();
                        }
                    }
                    ServerMessage::Snapshot(_) => {
                        if let Some(sender) = ready.take() {
                            let _ = sender.send(());
                        }
                    }
                    ServerMessage::Error { code, message } => {
                        return Err(Error::Server(format!("probe {code}: {message}")));
                    }
                    _ => {}
                }
            }
        }
    }
    let _ = sink.close().await;
    Ok(result)
}

/// The status line refreshes once a tick, so wait until it counts the whole
/// roster before a window opens; a loss is then a real close.
async fn await_counted(address: SocketAddr, expected: usize) -> Result<(), Error> {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Ok(status) = super::soak::fetch_status(address, "/status").await {
            if status.connections == expected {
                return Ok(());
            }
        }
        if Instant::now() > deadline {
            return Err(Error::Timeout("fanout roster in the status count"));
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

/// Poll `GET /status` until stopped; return when each connection was first
/// seen missing, in milliseconds after `since`.
async fn watch_connections(
    address: SocketAddr,
    since: Instant,
    expected: usize,
    mut stop: watch::Receiver<bool>,
) -> Vec<f64> {
    let mut losses = Vec::new();
    let mut seen = expected;
    let mut poll = tokio::time::interval(Duration::from_millis(100));
    poll.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tokio::select! {
            _ = stop.changed() => break,
            _ = poll.tick() => {
                let Ok(status) = super::soak::fetch_status(address, "/status").await else {
                    continue;
                };
                let at = since.elapsed().as_secs_f64() * 1000.0;
                while seen > status.connections {
                    seen -= 1;
                    losses.push(at);
                }
            }
        }
    }
    losses
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
        scenario: "baseline".into(),
        degraded: None,
        input: None,
        connection_losses_ms: Vec::new(),
        sockets: None,
    }
}

fn summarize_degraded(
    kind: WatcherKind,
    results: &[WatchResult],
    tick_starts: &BTreeMap<u64, Instant>,
) -> DegradedSummary {
    let mut summary = DegradedSummary {
        kind,
        watchers: results.len(),
        snapshots: 0,
        missing_snapshot_ticks: 0,
        closed_by_server: results
            .iter()
            .filter(|watcher| watcher.disconnected)
            .count(),
        tick_to_watcher_ms: Distribution::from_values(&[]),
    };
    let mut ages = Vec::new();
    for watcher in results {
        summary.snapshots += watcher.arrivals.len();
        for pair in watcher.arrivals.windows(2) {
            summary.missing_snapshot_ticks += pair[1].tick.saturating_sub(pair[0].tick + 1);
        }
        ages.extend(watcher.arrivals.iter().filter_map(|arrival| {
            let started = tick_starts.get(&arrival.tick)?;
            Some(arrival.at.saturating_duration_since(*started).as_secs_f64() * 1000.0)
        }));
    }
    summary.tick_to_watcher_ms = Distribution::from_values(&ages);
    summary
}

fn summarize_input(pattern: InputPattern, results: &[ProbeResult]) -> InputSummary {
    let samples: Vec<f64> = results
        .iter()
        .flat_map(|probe| probe.acked_ms.iter().copied())
        .collect();
    InputSummary {
        pattern,
        probes: results.len(),
        actions_sent: results.iter().map(|probe| probe.sent).sum(),
        actions_acked: samples.len() as u64,
        actions_unapplied: results.iter().map(|probe| probe.unapplied).sum(),
        input_to_ack_ms: Distribution::from_values(&samples),
        disconnects: results.iter().filter(|probe| probe.disconnected).count(),
    }
}

async fn one_row(spec: RowSpec, seed: u64, seconds: u64) -> Result<FanoutRow, Error> {
    spec.validate()?;
    let RowSpec {
        scenario,
        map,
        fighters,
        spectators,
        degraded,
        probes,
    } = spec;
    let mut row = measured_row(map, fighters, spectators, degraded, probes, seed, seconds).await?;
    row.scenario = scenario.into();
    Ok(row)
}

#[allow(clippy::too_many_lines)] // Start, roster, window, stop: one ordered row.
async fn measured_row(
    map: MapKind,
    fighters: usize,
    spectators: usize,
    degraded: Option<(WatcherKind, usize)>,
    probes: Option<(InputPattern, usize)>,
    seed: u64,
    seconds: u64,
) -> Result<FanoutRow, Error> {
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
    let mut probe_tasks = Vec::new();
    let mut probe_ready = Vec::new();
    if let Some((pattern, count)) = probes {
        for index in 0..count {
            let (tx, rx) = oneshot::channel();
            probe_ready.push(rx);
            probe_tasks.push(tokio::spawn(probe_task(
                url.clone(),
                index,
                pattern,
                tx,
                start_rx.clone(),
                stop_rx.clone(),
            )));
        }
    }
    for ready in probe_ready {
        tokio::time::timeout(Duration::from_secs(30), ready)
            .await
            .map_err(|_| Error::Timeout("fanout probe ready"))?
            .map_err(|_| Error::Server("fanout probe exited before ready".into()))?;
    }
    // Healthy watchers first, so they hold the same sources in every row.
    let kinds: Vec<WatcherKind> = std::iter::repeat_n(WatcherKind::Healthy, spectators)
        .chain(
            degraded
                .into_iter()
                .flat_map(|(kind, count)| std::iter::repeat_n(kind, count)),
        )
        .collect();
    let mut watcher_tasks = Vec::new();
    let mut watcher_ready = Vec::new();
    for (index, kind) in kinds.iter().enumerate() {
        let (tx, rx) = oneshot::channel();
        watcher_ready.push(rx);
        watcher_tasks.push(tokio::spawn(watcher_task(
            url.clone(),
            addr,
            watcher_source(index)?,
            format!("Watcher-{}", index + 1),
            *kind,
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
    let connections = fighters + kinds.len() + probe_tasks.len();
    await_counted(addr, connections).await?;
    metrics
        .lock()
        .map_err(|_| Error::Server("fanout metrics lock poisoned".into()))?
        .reset();
    let started = Instant::now();
    let _ = start_tx.send(Some(started));
    let losses = tokio::spawn(watch_connections(
        addr,
        started,
        connections,
        stop_rx.clone(),
    ));
    tokio::time::sleep(Duration::from_secs(seconds)).await;
    let elapsed = started.elapsed().as_secs_f64();
    // Kernel memory still held by the server side of every socket: a slow
    // or stalled reader pins its unsent bytes here, not in the queue.
    let sockets = super::traffic::host::socket_memory(addr.port()).ok();
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
    let mut probe_results = Vec::new();
    for task in probe_tasks {
        probe_results.push(
            tokio::time::timeout(Duration::from_secs(5), task)
                .await
                .map_err(|_| Error::Timeout("fanout probe stop"))?
                .map_err(|error| Error::Server(error.to_string()))??,
        );
    }
    let connection_losses_ms = tokio::time::timeout(Duration::from_secs(10), losses)
        .await
        .map_err(|_| Error::Timeout("fanout status poll stop"))?
        .map_err(|error| Error::Server(error.to_string()))?;
    let degraded_results = watcher_results.split_off(spectators);
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
    let degraded = degraded
        .map(|(kind, _)| summarize_degraded(kind, &degraded_results, &server_side.tick_starts));
    let mut row = measure_arrivals(
        map,
        fighters,
        spectators,
        seed,
        elapsed,
        watcher_results,
        server_side,
    );
    row.degraded = degraded;
    row.input = probes.map(|(pattern, _)| summarize_input(pattern, &probe_results));
    row.connection_losses_ms = connection_losses_ms;
    row.sockets = sockets;
    Ok(row)
}

fn report(seconds_per_row: u64, rows: Vec<FanoutRow>) -> FanoutReport {
    FanoutReport {
        schema: FANOUT_SCHEMA,
        build: fragr_server::metrics::build_info(),
        environment: fragr_server::bench::BenchEnvironment::current(),
        seconds_per_row,
        rows,
    }
}

fn check_seconds(seconds_per_row: u64) -> Result<(), Error> {
    if !(2..=120).contains(&seconds_per_row) {
        return Err(Error::Server("fanout seconds must be 2 through 120".into()));
    }
    Ok(())
}

/// Measure 4 and 16 active fighters against 1, 8, and 16 watchers on both
/// smallest and largest multiplayer maps. Every row starts a fresh seeded match.
pub async fn matrix(seconds_per_row: u64) -> Result<FanoutReport, Error> {
    check_seconds(seconds_per_row)?;
    let mut rows = Vec::new();
    for map in [MapKind::ArenaDuel, MapKind::TripointWorks] {
        for fighters in [4, 16] {
            for spectators in [1, 8, 16] {
                rows.push(
                    one_row(
                        RowSpec::plain(map, fighters, spectators),
                        42,
                        seconds_per_row,
                    )
                    .await?,
                );
            }
        }
    }
    Ok(report(seconds_per_row, rows))
}

/// A watcher that reads one frame every 100 ms: half the snapshot rate.
pub const SLOW_PAUSE_MS: u64 = 100;
/// Mean input rate for both probe patterns: a 60 Hz client.
pub const PROBE_HZ: u32 = 60;
/// A burst carries half a second of that input at once.
pub const PROBE_BURST: u32 = 30;
pub const PROBE_BURST_EVERY_MS: u64 = 500;

/// The stress rows on Tripoint Works, the largest arena: sixteen reflex
/// fighters and eight healthy watchers, then the same with four slow or four
/// stalled watchers, then four human input probes sending the same mean rate
/// steadily or in bursts.
pub fn stress_rows() -> Vec<RowSpec> {
    let base = RowSpec {
        scenario: "baseline",
        ..RowSpec::plain(MapKind::TripointWorks, 16, 8)
    };
    vec![
        base.clone(),
        RowSpec {
            scenario: "slow_readers",
            degraded: Some((
                WatcherKind::Slow {
                    pause_ms: SLOW_PAUSE_MS,
                },
                4,
            )),
            ..base.clone()
        },
        RowSpec {
            scenario: "stalled_readers",
            degraded: Some((WatcherKind::Stalled, 4)),
            ..base.clone()
        },
        RowSpec {
            scenario: "steady_input",
            probes: Some((InputPattern::Steady { hz: PROBE_HZ }, 4)),
            ..base.clone()
        },
        RowSpec {
            scenario: "bursty_input",
            probes: Some((
                InputPattern::Burst {
                    size: PROBE_BURST,
                    every_ms: PROBE_BURST_EVERY_MS,
                },
                4,
            )),
            ..base
        },
    ]
}

/// Run every stress row once, each on a fresh seeded match.
pub async fn stress(seconds_per_row: u64) -> Result<FanoutReport, Error> {
    check_seconds(seconds_per_row)?;
    let mut rows = Vec::new();
    for spec in stress_rows() {
        rows.push(one_row(spec, 42, seconds_per_row).await?);
    }
    Ok(report(seconds_per_row, rows))
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
            schema: FANOUT_SCHEMA,
            build: fragr_server::metrics::build_info(),
            environment: fragr_server::bench::BenchEnvironment::current(),
            seconds_per_row: 10,
            rows: vec![row],
        })
        .unwrap();
        assert_eq!(json["schema"], 3);
        assert_eq!(json["rows"][0]["scenario"], "baseline");
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

    #[test]
    fn an_ack_settles_every_action_it_covers() {
        let at = Instant::now();
        let mut pending = std::collections::VecDeque::from([
            (1, at),
            (2, at + Duration::from_millis(5)),
            (3, at + Duration::from_millis(10)),
        ]);
        let settled = settle_acks(&mut pending, 2, at + Duration::from_millis(20));
        assert_eq!(settled, vec![20.0, 15.0]);
        assert_eq!(pending.len(), 1);
        // An older Ack settles nothing more.
        assert!(settle_acks(&mut pending, 1, at + Duration::from_millis(30)).is_empty());
        let input = summarize_input(
            InputPattern::Steady { hz: 60 },
            &[ProbeResult {
                sent: 3,
                acked_ms: settled,
                unapplied: 1,
                disconnected: true,
            }],
        );
        assert_eq!((input.actions_sent, input.actions_acked), (3, 2));
        assert_eq!(input.actions_unapplied, 1);
        assert_eq!(input.input_to_ack_ms.max, 20.0);
        assert_eq!(input.disconnects, 1);
    }

    #[test]
    fn degraded_watchers_count_gaps_and_server_closes() {
        let at = Instant::now();
        let summary = summarize_degraded(
            WatcherKind::Slow { pause_ms: 100 },
            &[
                WatchResult {
                    arrivals: vec![
                        Arrival { tick: 4, at },
                        Arrival { tick: 7, at },
                        Arrival {
                            tick: 8,
                            at: at + Duration::from_millis(300),
                        },
                    ],
                    text_bytes: 0,
                    disconnected: true,
                },
                WatchResult::default(),
            ],
            &BTreeMap::from([(8, at)]),
        );
        // Only tick 8 has a recorded start: read 300 ms after it began.
        assert_eq!(summary.tick_to_watcher_ms.samples, 1);
        assert_eq!(summary.tick_to_watcher_ms.max, 300.0);
        assert_eq!(summary.watchers, 2);
        assert_eq!(summary.snapshots, 3);
        assert_eq!(summary.missing_snapshot_ticks, 2);
        assert_eq!(summary.closed_by_server, 1);
    }

    #[test]
    fn rows_respect_the_admission_caps() {
        let rows = stress_rows();
        assert_eq!(rows.len(), 5);
        for row in &rows {
            row.validate().unwrap();
        }
        let names: Vec<&str> = rows.iter().map(|row| row.scenario).collect();
        assert_eq!(
            names,
            [
                "baseline",
                "slow_readers",
                "stalled_readers",
                "steady_input",
                "bursty_input"
            ]
        );
        let mut crowded = RowSpec::plain(MapKind::TripointWorks, 4, 12);
        crowded.degraded = Some((WatcherKind::Stalled, 5));
        assert!(crowded.validate().is_err(), "seventeen spectators");
        let mut healthy = RowSpec::plain(MapKind::TripointWorks, 4, 4);
        healthy.degraded = Some((WatcherKind::Healthy, 1));
        assert!(healthy.validate().is_err());
        let mut idle = RowSpec::plain(MapKind::TripointWorks, 4, 4);
        idle.probes = Some((InputPattern::Steady { hz: 20 }, 0));
        assert!(idle.validate().is_err());
        assert!(RowSpec::plain(MapKind::TripointWorks, 30, 4)
            .validate()
            .is_err());
        assert_eq!(
            InputPattern::Steady { hz: 20 }.period(),
            Duration::from_millis(50)
        );
        assert_eq!(InputPattern::Steady { hz: 20 }.per_period(), 1);
        let burst = InputPattern::Burst {
            size: 30,
            every_ms: 500,
        };
        assert_eq!(
            (burst.period(), burst.per_period()),
            (Duration::from_millis(500), 30)
        );
        assert!(check_seconds(1).is_err() && check_seconds(2).is_ok());
    }

    /// A short live row with every kind of client: the stalled watcher is
    /// closed by the server or still open, never a harness failure, and the
    /// probes' actions are acknowledged.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn a_short_stress_row_measures_degraded_watchers_and_probes() {
        let slow = measured_row(
            MapKind::ArenaDuel,
            2,
            1,
            Some((WatcherKind::Slow { pause_ms: 100 }, 1)),
            Some((
                InputPattern::Burst {
                    size: 4,
                    every_ms: 200,
                },
                1,
            )),
            7,
            2,
        )
        .await
        .unwrap();
        let degraded = slow.degraded.as_ref().unwrap();
        assert_eq!(degraded.watchers, 1);
        assert!(degraded.snapshots > 0);
        let input = slow.input.as_ref().unwrap();
        assert!(input.actions_sent >= 8, "{input:?}");
        // Every action is timed, set aside untimed (down, or before the first
        // applied Ack), or still pending when the window closes. A short
        // window can fall entirely inside one respawn, so either may be zero.
        let settled = input.actions_acked + input.actions_unapplied;
        assert!(settled > 0 && settled <= input.actions_sent, "{input:?}");
        assert!(slow.server_metrics["tick_ms"]["count"].as_u64().unwrap() > 0);
        let stalled = one_row(
            RowSpec {
                scenario: "stalled_readers",
                degraded: Some((WatcherKind::Stalled, 1)),
                ..RowSpec::plain(MapKind::ArenaDuel, 2, 1)
            },
            7,
            2,
        )
        .await
        .unwrap();
        assert_eq!(stalled.scenario, "stalled_readers");
        let degraded = stalled.degraded.as_ref().unwrap();
        assert_eq!(degraded.snapshots, 0);
        assert!(stalled.watcher_snapshots > 0);
    }
}
