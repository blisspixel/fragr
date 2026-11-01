//! Peeker's advantage over real sockets with an injected link (#525).
//!
//! Two human clients join one in-process server through the loopback link
//! shaper (`crate::link`), each direction delayed by half the round trip.
//! The peeker rests, then at a seeded phase of the tick presses a strafe and
//! holds it, as a fighter stepping out from a corner. The holder only
//! watches. Every snapshot the holder's socket delivers is stamped on
//! arrival; afterwards the holder's own client is replayed over those
//! arrivals: it reads its socket at 60 Hz frames and draws the peeker with
//! `RemotePresentation`'s adaptive timeline (`crate::presentation`).
//!
//! The measure is the time from the peeker's press to the first holder frame
//! that draws the peeker moved. The peeker sees its own body move on its next
//! frame through prediction (about 8 to 25 ms, `tools/qa_feel.sh`), so this
//! is the upper bound of the peeker's advantage: the head start a peeker has
//! before the player holding the angle can see it. Valorant's published
//! baseline for the same quantity is about 141 ms; fragr's target is under
//! 150 ms at a 50 ms round trip.
//!
//! What it is not: one machine, a modelled link on loopback, and a modelled
//! holder frame clock rather than a rendered frame.

use crate::link::LinkProfile;
use crate::presentation::{Timeline, TICK_USEC};
use crate::{transport, Error, TICKS_PER_SECOND};
use fragr_server::protocol::{Action, ClientMessage, Role, ServerMessage};
use fragr_server::run::{run_server_with_metrics, RunMetrics, ServerOptions};
use fragr_server::sim::{MapKind, MatchConfig};
use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::{oneshot, watch};
use tokio_tungstenite::{client_async, tungstenite::Message};
use uuid::Uuid;

/// Report schema.
pub const PEEK_SCHEMA: u32 = 1;
/// The round trips the probe covers by default.
pub const RTTS_MS: [u32; 4] = [0, 50, 100, 150];
/// The gate: under 150 ms at a 50 ms round trip.
pub const TARGET_MS: f64 = 150.0;
const FRAME_USEC: i64 = 16_667;
/// Rest before each peek, so the peeker is still and the holder's buffer
/// has drawn it still.
const REST: Duration = Duration::from_millis(900);
const HOLD: Duration = Duration::from_millis(350);
const SEND_EVERY: Duration = Duration::from_micros(16_667);
/// Drawn displacement that counts as visibly moved: under a pixel at 20 m.
const MOVED_M: f64 = 0.01;

#[derive(Debug, Clone, Serialize)]
pub struct PeekRow {
    pub rtt_ms: u32,
    pub jitter_ms: u32,
    pub trials: u32,
    /// Trials whose peek the holder saw move (a wall can stop a strafe).
    pub measured: u32,
    /// Peeker press to the holder's first frame drawing the move.
    pub p50_ms: f64,
    pub mean_ms: f64,
    pub p95_ms: f64,
    pub max_ms: f64,
    /// The holder's interpolation buffer at those frames.
    pub mean_buffer_ms: f64,
    /// The same arrivals drawn by the client before #525, two ticks behind.
    pub before_mean_ms: f64,
    pub before_p95_ms: f64,
    /// Holder frames that starved during the peeks.
    pub starved_frames: u32,
}

#[derive(Debug, Clone, Serialize)]
pub struct PeekReport {
    pub schema: u32,
    pub seed: u64,
    pub map: String,
    pub rows: Vec<PeekRow>,
}

fn quantile(sorted: &[f64], q: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    sorted[((sorted.len() - 1) as f64 * q).round() as usize]
}

/// One snapshot as the holder's socket delivered it.
#[derive(Debug, Clone, Copy)]
pub struct Arrival {
    pub usec: i64,
    pub tick: u64,
    /// The peeker's feet, absent while it is not in the world.
    pub peeker: Option<[f64; 3]>,
}

/// What the holder drew and when, from `arrivals` read at 60 Hz frames
/// starting at `phase_usec`. Returns the delay from each press to the first
/// frame drawing the peeker `MOVED_M` from where that press's frame drew it,
/// the buffer then, and the count of starved frames inside the peeks.
pub fn holder_delays(
    arrivals: &[Arrival],
    presses: &[i64],
    phase_usec: i64,
) -> (Vec<(f64, f64)>, u32) {
    holder_delays_on(Timeline::default(), arrivals, presses, phase_usec)
}

fn holder_delays_on(
    mut timeline: Timeline,
    arrivals: &[Arrival],
    presses: &[i64],
    phase_usec: i64,
) -> (Vec<(f64, f64)>, u32) {
    let Some(first) = arrivals.first() else {
        return (Vec::new(), 0);
    };
    let end = arrivals.last().map_or(0, |a| a.usec) + 500_000;
    let mut next = 0usize;
    let mut now = first.usec + phase_usec.rem_euclid(FRAME_USEC);
    let mut drawn: Vec<(i64, Option<[f64; 3]>, f64, bool)> = Vec::new();
    while now <= end {
        while next < arrivals.len() && arrivals[next].usec <= now {
            let arrival = arrivals[next];
            match arrival.peeker {
                Some(feet) => {
                    timeline.accept(arrival.tick, feet, now);
                }
                None => timeline.reset(),
            }
            next += 1;
        }
        let shown = timeline.sample(now);
        drawn.push((
            now,
            shown.map(|d| d.position),
            timeline.buffer_ticks,
            timeline.starved,
        ));
        now += FRAME_USEC;
    }
    let mut delays = Vec::new();
    let mut starved = 0u32;
    for &press in presses {
        let Some(start) = drawn.iter().position(|frame| frame.0 >= press) else {
            continue;
        };
        let Some(rest) = drawn[start].1 else {
            continue;
        };
        let window = drawn[start..]
            .iter()
            .take_while(|frame| frame.0 < press + 1_000_000);
        for frame in window {
            starved += u32::from(frame.3);
            let Some(at) = frame.1 else {
                break;
            };
            let moved = ((at[0] - rest[0]).powi(2) + (at[2] - rest[2]).powi(2)).sqrt();
            if moved > MOVED_M {
                delays.push(((frame.0 - press) as f64 / 1000.0, frame.2));
                break;
            }
        }
    }
    (delays, starved)
}

fn hello(name: &str) -> Result<Message, Error> {
    Ok(Message::Text(
        serde_json::to_string(&ClientMessage::Hello {
            body: None,
            seat: None,
            gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
            geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
            role: Role::Human,
            name: name.into(),
            ticket: fragr_server::join_ticket::ticket_for(Role::Human),
            resume: None,
        })
        .map_err(transport)?,
    ))
}

type Socket = tokio_tungstenite::WebSocketStream<tokio::net::TcpStream>;

async fn connect(relay: SocketAddr, url: &str, name: &str) -> Result<Socket, Error> {
    let stream = tokio::net::TcpStream::connect(relay)
        .await
        .map_err(transport)?;
    let (mut socket, _) = client_async(url, stream).await.map_err(transport)?;
    socket.send(hello(name)?).await.map_err(transport)?;
    Ok(socket)
}

/// The holder: stamp every snapshot until `stop`.
async fn holder_task(
    mut socket: Socket,
    epoch: Instant,
    mut peeker: watch::Receiver<Option<Uuid>>,
    mut stop: watch::Receiver<bool>,
    ready: oneshot::Sender<()>,
) -> Result<Vec<Arrival>, Error> {
    let mut world = fragr_server::protocol::WorldReader::new();
    let mut arrivals = Vec::new();
    let mut ready = Some(ready);
    loop {
        let message = tokio::select! {
            _ = stop.changed() => break,
            _ = peeker.changed() => continue,
            message = socket.next() => message,
        };
        let Some(Ok(Message::Text(text))) = message else {
            match message {
                None | Some(Err(_)) | Some(Ok(Message::Close(_))) => {
                    return Err(Error::Server("holder socket closed".into()))
                }
                _ => continue,
            }
        };
        let usec = epoch.elapsed().as_micros() as i64;
        if let Ok(ServerMessage::Snapshot(snapshot)) = world.read(&text) {
            if let Some(ready) = ready.take() {
                let _ = ready.send(());
            }
            let id = *peeker.borrow();
            let feet = id.and_then(|id| {
                snapshot
                    .players
                    .iter()
                    .find(|p| p.id == id && p.hp > 0)
                    .map(|p| [f64::from(p.x), f64::from(p.y), f64::from(p.z)])
            });
            arrivals.push(Arrival {
                usec,
                tick: snapshot.tick,
                peeker: feet,
            });
        }
    }
    let _ = socket.close(None).await;
    Ok(arrivals)
}

fn strafe(seq: u32, direction: i8) -> Result<Message, Error> {
    Ok(Message::Text(
        serde_json::to_string(&ClientMessage::Action(Action {
            left: direction < 0,
            right: direction > 0,
            yaw: Some(0.0),
            seq: Some(seq),
            ..Action::default()
        }))
        .map_err(transport)?,
    ))
}

/// The peeker: rest, press at a seeded phase, hold, repeat. Returns each
/// press time.
async fn peeker_task(
    socket: Socket,
    epoch: Instant,
    trials: u32,
    seed: u64,
    id_tx: watch::Sender<Option<Uuid>>,
) -> Result<Vec<i64>, Error> {
    let (mut sink, mut stream) = socket.split();
    let (id_once, id_rx) = oneshot::channel::<Uuid>();
    // Keep reading: pings, deltas and the Welcome that names this fighter.
    let reader = tokio::spawn(async move {
        let mut id_once = Some(id_once);
        while let Some(Ok(message)) = stream.next().await {
            if let Message::Text(text) = message {
                if let Ok(ServerMessage::Welcome {
                    player_id: Some(id),
                    ..
                }) = serde_json::from_str::<ServerMessage>(&text)
                {
                    if let Some(once) = id_once.take() {
                        let _ = once.send(id);
                    }
                }
            }
        }
    });
    let id = tokio::time::timeout(Duration::from_secs(20), id_rx)
        .await
        .map_err(|_| Error::Timeout("peeker welcome"))?
        .map_err(|_| Error::Server("peeker closed before welcome".into()))?;
    let _ = id_tx.send(Some(id));
    let mut seq = 0u32;
    let mut presses = Vec::new();
    let mut state = seed | 1;
    let send = |direction: i8, seq: &mut u32| {
        *seq += 1;
        strafe(*seq, direction)
    };
    // Settle: the holder's clock measures the link before the first peek.
    let settle = Instant::now() + Duration::from_secs(3);
    while Instant::now() < settle {
        sink.send(send(0, &mut seq)?).await.map_err(transport)?;
        tokio::time::sleep(SEND_EVERY).await;
    }
    for trial in 0..trials {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        let phase = Duration::from_micros(state % TICK_USEC as u64);
        let rest_until = Instant::now() + REST + phase;
        while Instant::now() < rest_until {
            sink.send(send(0, &mut seq)?).await.map_err(transport)?;
            tokio::time::sleep(
                SEND_EVERY.min(rest_until.saturating_duration_since(Instant::now())),
            )
            .await;
        }
        // Alternate sides so the peeker stays near where it spawned.
        let direction = if trial % 2 == 0 { 1 } else { -1 };
        presses.push(epoch.elapsed().as_micros() as i64);
        let hold_until = Instant::now() + HOLD;
        while Instant::now() < hold_until {
            sink.send(send(direction, &mut seq)?)
                .await
                .map_err(transport)?;
            tokio::time::sleep(SEND_EVERY).await;
        }
    }
    let rest_until = Instant::now() + Duration::from_millis(1200);
    while Instant::now() < rest_until {
        sink.send(send(0, &mut seq)?).await.map_err(transport)?;
        tokio::time::sleep(SEND_EVERY).await;
    }
    let _ = sink.close().await;
    reader.abort();
    Ok(presses)
}

/// One row: a fresh server, one link, `trials` peeks.
pub async fn run_row(
    map: MapKind,
    rtt_ms: u32,
    jitter_ms: u32,
    trials: u32,
    seed: u64,
) -> Result<PeekRow, Error> {
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let (bound_tx, bound_rx) = oneshot::channel();
    let metrics = Arc::new(Mutex::new(RunMetrics::default()));
    let seconds = 10 + u64::from(trials) * 2;
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
            metrics,
        )
        .await
        .map_err(|error| error.to_string())
    });
    let addr = tokio::time::timeout(Duration::from_secs(30), bound_rx)
        .await
        .map_err(|_| Error::Timeout("peek server bind"))?
        .map_err(|_| Error::Server("peek server exited before bind".into()))?;
    let profile = LinkProfile {
        jitter_ms: u64::from(jitter_ms),
        ..LinkProfile::clean("peek", 100_000, u64::from(rtt_ms / 2))
    };
    let relay = crate::link::start(addr, profile, seed)
        .await
        .map_err(Error::Server)?;
    let url = format!("ws://{addr}/");
    let epoch = Instant::now();
    let (stop_tx, stop_rx) = watch::channel(false);
    let (id_tx, id_rx) = watch::channel(None);
    let (ready_tx, ready_rx) = oneshot::channel();
    let holder_socket = connect(relay.addr, &url, "Holder").await?;
    let holder = tokio::spawn(holder_task(holder_socket, epoch, id_rx, stop_rx, ready_tx));
    tokio::time::timeout(Duration::from_secs(20), ready_rx)
        .await
        .map_err(|_| Error::Timeout("holder first snapshot"))?
        .map_err(|_| Error::Server("holder closed before a snapshot".into()))?;
    let peeker_socket = connect(relay.addr, &url, "Peeker").await?;
    let presses = peeker_task(peeker_socket, epoch, trials, seed, id_tx).await;
    let _ = stop_tx.send(true);
    let arrivals = holder.await.map_err(|e| Error::Server(e.to_string()))??;
    let _ = shutdown_tx.send(());
    let _ = server.await;
    let presses = presses?;
    let (delays, starved_frames) = holder_delays(&arrivals, &presses, seed as i64);
    let mut sorted: Vec<f64> = delays.iter().map(|d| d.0).collect();
    sorted.sort_by(f64::total_cmp);
    let n = delays.len().max(1) as f64;
    let (before, _) = holder_delays_on(Timeline::pinned(2.0), &arrivals, &presses, seed as i64);
    let mut before: Vec<f64> = before.iter().map(|d| d.0).collect();
    before.sort_by(f64::total_cmp);
    Ok(PeekRow {
        rtt_ms,
        jitter_ms,
        trials,
        measured: delays.len() as u32,
        p50_ms: quantile(&sorted, 0.5),
        mean_ms: sorted.iter().sum::<f64>() / n,
        p95_ms: quantile(&sorted, 0.95),
        max_ms: sorted.last().copied().unwrap_or(0.0),
        mean_buffer_ms: delays.iter().map(|d| d.1).sum::<f64>() / n * TICK_USEC as f64 / 1000.0,
        before_mean_ms: before.iter().sum::<f64>() / before.len().max(1) as f64,
        before_p95_ms: quantile(&before, 0.95),
        starved_frames,
    })
}

pub async fn run(
    map: MapKind,
    rtts: &[u32],
    jitter_ms: u32,
    trials: u32,
    seed: u64,
) -> Result<PeekReport, Error> {
    let mut rows = Vec::new();
    for &rtt in rtts {
        rows.push(
            run_row(
                map,
                rtt,
                jitter_ms,
                trials,
                seed.wrapping_add(u64::from(rtt)),
            )
            .await?,
        );
    }
    Ok(PeekReport {
        schema: PEEK_SCHEMA,
        seed,
        map: map.name().to_string(),
        rows,
    })
}

/// Problems for `--assert`: the 50 ms row's mean over the target, or rows
/// that measured too few peeks to say anything.
pub fn check(report: &PeekReport) -> Vec<String> {
    let mut problems = Vec::new();
    for row in &report.rows {
        if row.measured * 2 < row.trials {
            problems.push(format!(
                "{} ms: measured {} of {} peeks",
                row.rtt_ms, row.measured, row.trials
            ));
        }
        if row.rtt_ms == 50 && row.jitter_ms == 0 && row.mean_ms >= TARGET_MS {
            problems.push(format!(
                "peeker's advantage at 50 ms round trip is {:.0} ms, target under {TARGET_MS:.0}",
                row.mean_ms
            ));
        }
    }
    problems
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A peeker that starts moving at tick 40 on a link whose snapshots
    /// arrive 25 ms after their tick.
    fn arrivals(one_way_usec: i64) -> Vec<Arrival> {
        (1..=80u64)
            .map(|tick| Arrival {
                usec: tick as i64 * TICK_USEC + one_way_usec,
                tick,
                peeker: Some([(tick.saturating_sub(40) as f64) * 0.3, 0.0, 0.0]),
            })
            .collect()
    }

    #[test]
    fn the_holder_sees_a_peek_one_trip_a_tick_and_its_buffer_late() {
        // The press at 1.97 s reaches the server 25 ms later and tick 40
        // (2.0 s) is still the last still one; tick 41 moves. Its snapshot
        // arrives at 2.075 s and the holder draws past tick 40 once its
        // render time, 1.2 ticks behind the arrival schedule, passes 40.
        let press = 39 * TICK_USEC + 20_000 - 25_000;
        let (delays, starved) = holder_delays(&arrivals(25_000), &[press], 0);
        assert_eq!(starved, 0);
        let (delay, buffer) = delays[0];
        assert!((buffer - 1.2).abs() < 0.01, "{buffer}");
        // Render time reaches tick 40 at 40 * 50 + 25 + 60 ms = 2.085 s; it is
        // then 1 cm along within a further 2 ms; frames add up to 16.7 ms.
        let floor = (40 * TICK_USEC + 25_000 + 60_000 - press) as f64 / 1000.0;
        assert!(
            delay >= floor && delay <= floor + 2.0 + 16.7,
            "{delay} against {floor}"
        );
        let (before, _) = holder_delays_on(Timeline::pinned(2.0), &arrivals(25_000), &[press], 0);
        assert!(
            (before[0].0 - delay - 40.0).abs() <= 16.7,
            "{before:?} against {delay}"
        );
    }

    #[test]
    fn a_wall_or_a_missing_peeker_is_not_measured() {
        let still: Vec<Arrival> = arrivals(25_000)
            .into_iter()
            .map(|a| Arrival {
                peeker: Some([0.0; 3]),
                ..a
            })
            .collect();
        assert!(holder_delays(&still, &[2_000_000], 0).0.is_empty());
        let gone: Vec<Arrival> = arrivals(25_000)
            .into_iter()
            .map(|a| Arrival { peeker: None, ..a })
            .collect();
        assert!(holder_delays(&gone, &[2_000_000], 0).0.is_empty());
        assert!(holder_delays(&[], &[1], 0).0.is_empty());
        let report = PeekReport {
            schema: PEEK_SCHEMA,
            seed: 1,
            map: "x".into(),
            rows: vec![PeekRow {
                rtt_ms: 50,
                jitter_ms: 0,
                trials: 10,
                measured: 2,
                p50_ms: 160.0,
                mean_ms: 160.0,
                p95_ms: 170.0,
                max_ms: 170.0,
                mean_buffer_ms: 60.0,
                before_mean_ms: 200.0,
                before_p95_ms: 210.0,
                starved_frames: 0,
            }],
        };
        assert_eq!(check(&report).len(), 2);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn two_clients_over_a_delayed_link_measure_a_peek() {
        let row = run_row(MapKind::ArenaDuel, 50, 0, 3, 7).await.unwrap();
        assert!(row.measured >= 2, "{row:?}");
        // One-way trips, a tick wait and the buffer: well above the round
        // trip, and bounded by a loaded test host.
        assert!(row.mean_ms > 50.0 && row.max_ms < 400.0, "{row:?}");
        // The two-tick client drew the same peek about 40 ms later.
        assert!(row.before_mean_ms > row.mean_ms + 20.0, "{row:?}");
    }
}
