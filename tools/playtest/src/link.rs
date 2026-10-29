//! A loopback link shaper (#434): a TCP relay in this process that stands
//! between real WebSocket clients and the real server and imposes a link's
//! capacity, delay, jitter, loss and outages on the bytes it carries.
//!
//! It is a simulated link on loopback, not a network. It shapes the stream
//! the way a TCP connection over such a link delivers it, not packets:
//!
//! - **Capacity.** Each direction serializes its bytes at the link's rate,
//!   so a chunk leaves only when the link has finished the one before it.
//! - **Delay and jitter.** A chunk then arrives after the one-way delay plus
//!   a seeded draw from 0 to `jitter_ms`. The stream is ordered, so a late
//!   chunk holds back every chunk behind it, as TCP would.
//! - **Loss.** TCP never shows a reader a lost segment, only a gap in time
//!   until it is retransmitted: a lost chunk arrives `loss_stall_ms` late
//!   and holds back what follows.
//! - **Outages.** Nothing arrives during `outage_ms` of every
//!   `outage_every_ms`; what was due waits for the window to end.
//! - **Backpressure.** The link holds at most `queue_bytes` that it has
//!   taken from the sender and not yet delivered: its window and its
//!   bottleneck queue together. Past that the relay stops reading, the
//!   relay's own small receive buffer fills, and the sender's socket blocks,
//!   as a full TCP window blocks a real server's writer.
//!
//! The relay connects to the server from the client's own source address,
//! so per-address admission sees the same roster it would without a link.

use serde::Serialize;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpSocket, TcpStream};
use tokio::sync::{mpsc, Semaphore};
use tokio::time::Instant;

/// One simulated link, the same in both directions except capacity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct LinkProfile {
    pub name: &'static str,
    /// Server to client capacity, bytes per second.
    pub down_bytes_per_s: u64,
    /// Client to server capacity, bytes per second.
    pub up_bytes_per_s: u64,
    /// One-way delay each direction, milliseconds.
    pub delay_ms: u64,
    /// Extra one-way delay per chunk, drawn uniformly from 0 to this.
    pub jitter_ms: u64,
    /// Chunks in a thousand that lose a segment.
    pub loss_per_mille: u32,
    /// What a lost segment costs the stream: the retransmission's delay.
    pub loss_stall_ms: u64,
    /// A periodic outage: every this many milliseconds (0 for none) ...
    pub outage_every_ms: u64,
    /// ... nothing arrives for this long.
    pub outage_ms: u64,
    /// Bytes the link holds in flight and queued, each direction.
    pub queue_bytes: usize,
}

impl LinkProfile {
    /// A link with only capacity and delay; set the rest with struct update.
    pub const fn clean(name: &'static str, down_kbit: u64, delay_ms: u64) -> Self {
        Self {
            name,
            down_bytes_per_s: down_kbit * 125,
            up_bytes_per_s: down_kbit * 125,
            delay_ms,
            jitter_ms: 0,
            loss_per_mille: 0,
            loss_stall_ms: 0,
            outage_every_ms: 0,
            outage_ms: 0,
            queue_bytes: 64 * 1024,
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.down_bytes_per_s == 0 || self.up_bytes_per_s == 0 {
            return Err(format!("link {} has no capacity", self.name));
        }
        if self.queue_bytes < 1024 || self.loss_per_mille > 1000 {
            return Err(format!("link {} is malformed", self.name));
        }
        if self.outage_every_ms > 0 && self.outage_ms >= self.outage_every_ms {
            return Err(format!("link {} is never up", self.name));
        }
        Ok(())
    }
}

/// What the links of one relay did, summed over connections and directions.
#[derive(Debug, Default)]
struct Counters {
    connections: AtomicU64,
    down_bytes: AtomicU64,
    up_bytes: AtomicU64,
    lost_chunks: AtomicU64,
    /// Nanoseconds the server-to-client side spent unable to take more bytes
    /// because the link was full: backpressure into the server's socket.
    down_blocked_ns: AtomicU64,
    down_peak_queue: AtomicU64,
}

#[derive(Debug, Clone, Default, Serialize, PartialEq)]
pub struct LinkReport {
    pub connections: u64,
    pub down_bytes: u64,
    pub up_bytes: u64,
    pub lost_chunks: u64,
    /// Time the server-to-client link was full and refused more bytes,
    /// summed over connections.
    pub down_blocked_ms: f64,
    /// The most bytes one server-to-client link held at once.
    pub down_peak_queue_bytes: u64,
}

/// A running relay. Dropping it stops accepting; open links end with their
/// sockets.
pub struct Relay {
    pub addr: SocketAddr,
    counters: Arc<Counters>,
    accept: tokio::task::JoinHandle<()>,
}

impl Drop for Relay {
    fn drop(&mut self) {
        self.accept.abort();
    }
}

impl Relay {
    pub fn report(&self) -> LinkReport {
        let c = &self.counters;
        LinkReport {
            connections: c.connections.load(Ordering::Relaxed),
            down_bytes: c.down_bytes.load(Ordering::Relaxed),
            up_bytes: c.up_bytes.load(Ordering::Relaxed),
            lost_chunks: c.lost_chunks.load(Ordering::Relaxed),
            down_blocked_ms: c.down_blocked_ns.load(Ordering::Relaxed) as f64 / 1e6,
            down_peak_queue_bytes: c.down_peak_queue.load(Ordering::Relaxed),
        }
    }

    /// Zero the counters at the start of a measured window.
    pub fn reset(&self) {
        let c = &self.counters;
        for counter in [
            &c.down_bytes,
            &c.up_bytes,
            &c.lost_chunks,
            &c.down_blocked_ns,
            &c.down_peak_queue,
        ] {
            counter.store(0, Ordering::Relaxed);
        }
    }
}

/// The relay's receive buffer toward the sender. Small, so bytes wait in the
/// sender's socket rather than in a kernel buffer Linux would grow to
/// megabytes on loopback.
const RELAY_RECV_BUFFER: u32 = 16 * 1024;
/// Largest chunk one read takes.
const CHUNK: usize = 16 * 1024;

/// Listen on loopback and relay every connection to `upstream` through
/// `profile`. Jitter and loss draws are seeded per connection from `seed`.
pub async fn start(upstream: SocketAddr, profile: LinkProfile, seed: u64) -> Result<Relay, String> {
    profile.validate()?;
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| format!("link relay bind: {e}"))?;
    let addr = listener
        .local_addr()
        .map_err(|e| format!("link relay address: {e}"))?;
    let counters = Arc::new(Counters::default());
    let shared = Arc::clone(&counters);
    let accept = tokio::spawn(async move {
        let mut index = 0u64;
        while let Ok((client, peer)) = listener.accept().await {
            index += 1;
            shared.connections.fetch_add(1, Ordering::Relaxed);
            let counters = Arc::clone(&shared);
            let seed = seed ^ index.wrapping_mul(0x9E37_79B9_7F4A_7C15);
            tokio::spawn(async move {
                if let Ok(server) = connect_upstream(upstream, peer).await {
                    relay(client, server, profile, seed, counters).await;
                }
            });
        }
    });
    Ok(Relay {
        addr,
        counters,
        accept,
    })
}

async fn connect_upstream(upstream: SocketAddr, peer: SocketAddr) -> std::io::Result<TcpStream> {
    let socket = TcpSocket::new_v4()?;
    socket.set_recv_buffer_size(RELAY_RECV_BUFFER)?;
    socket.bind(SocketAddr::new(peer.ip(), 0))?;
    let stream = socket.connect(upstream).await?;
    stream.set_nodelay(true)?;
    Ok(stream)
}

async fn relay(
    client: TcpStream,
    server: TcpStream,
    profile: LinkProfile,
    seed: u64,
    counters: Arc<Counters>,
) {
    let _ = client.set_nodelay(true);
    let epoch = Instant::now();
    let (client_read, client_write) = client.into_split();
    let (server_read, server_write) = server.into_split();
    let down = Direction {
        rate: profile.down_bytes_per_s,
        down: true,
    };
    let up = Direction {
        rate: profile.up_bytes_per_s,
        down: false,
    };
    let downlink = shape(
        server_read,
        client_write,
        profile,
        down,
        Draws::new(seed),
        epoch,
        Arc::clone(&counters),
    );
    let uplink = shape(
        client_read,
        server_write,
        profile,
        up,
        Draws::new(seed ^ 0x5555),
        epoch,
        counters,
    );
    // Either side closing ends the link.
    tokio::select! {
        () = downlink => {}
        () = uplink => {}
    }
}

#[derive(Clone, Copy)]
struct Direction {
    rate: u64,
    down: bool,
}

/// Seeded draws, owned per direction so timing never shares a stream.
struct Draws(u64);

impl Draws {
    fn new(seed: u64) -> Self {
        Self(seed.max(1))
    }
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    fn below(&mut self, n: u64) -> u64 {
        if n == 0 {
            0
        } else {
            self.next() % n
        }
    }
}

/// When a chunk taken at `now` reaches the far side, and when the link is
/// free for the next one. Pure, so the schedule is testable without sockets.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Schedule {
    /// The link finishes serializing the previous chunk at this offset.
    pub free_at: Duration,
    /// The previous chunk arrived at this offset; order is kept.
    pub last_arrival: Duration,
}

impl Schedule {
    /// Offsets are from the link's start.
    pub fn arrival(
        &mut self,
        profile: &LinkProfile,
        rate: u64,
        now: Duration,
        bytes: usize,
        jitter: Duration,
        lost: bool,
    ) -> Duration {
        let departure = self.free_at.max(now);
        let serialize = Duration::from_secs_f64(bytes as f64 / rate as f64);
        self.free_at = departure + serialize;
        let mut arrival = self.free_at + Duration::from_millis(profile.delay_ms) + jitter;
        if lost {
            arrival += Duration::from_millis(profile.loss_stall_ms);
        }
        arrival = arrival.max(self.last_arrival);
        if profile.outage_every_ms > 0 {
            let every = profile.outage_every_ms as u128;
            let at = arrival.as_millis();
            let into = at % every;
            // Each period opens with its outage, after the first period.
            if at >= every && into < u128::from(profile.outage_ms) {
                arrival = Duration::from_millis((at - into + u128::from(profile.outage_ms)) as u64);
            }
        }
        self.last_arrival = arrival;
        arrival
    }
}

async fn shape<R, W>(
    mut from: R,
    to: W,
    profile: LinkProfile,
    direction: Direction,
    mut draws: Draws,
    epoch: Instant,
    counters: Arc<Counters>,
) where
    R: tokio::io::AsyncRead + Unpin,
    W: tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let room = Arc::new(Semaphore::new(profile.queue_bytes));
    let (tx, rx) = mpsc::unbounded_channel::<(Instant, Vec<u8>)>();
    let deliver = tokio::spawn(deliver(
        rx,
        to,
        Arc::clone(&room),
        Arc::clone(&counters),
        direction,
    ));
    let mut schedule = Schedule {
        free_at: Duration::ZERO,
        last_arrival: Duration::ZERO,
    };
    let chunk = CHUNK.min(profile.queue_bytes);
    let mut buffer = vec![0u8; chunk];
    loop {
        // Wait for room for a whole chunk before reading, so a full link
        // stops reading and the sender's socket fills.
        let wait = Instant::now();
        let Ok(permit) = Arc::clone(&room).acquire_many_owned(chunk as u32).await else {
            break;
        };
        if direction.down {
            let waited = wait.elapsed();
            if waited > Duration::from_millis(1) {
                counters
                    .down_blocked_ns
                    .fetch_add(waited.as_nanos() as u64, Ordering::Relaxed);
            }
        }
        let read = match from.read(&mut buffer).await {
            Ok(0) | Err(_) => break,
            Ok(read) => read,
        };
        // Keep only the room this chunk uses; the delivery side returns it.
        drop(permit);
        let Ok(held) = room.acquire_many(read as u32).await else {
            break;
        };
        held.forget();
        if direction.down {
            let queued = (profile.queue_bytes - room.available_permits()) as u64;
            counters
                .down_peak_queue
                .fetch_max(queued, Ordering::Relaxed);
        }
        let lost = draws.below(1000) < u64::from(profile.loss_per_mille);
        if lost {
            counters.lost_chunks.fetch_add(1, Ordering::Relaxed);
        }
        let jitter = Duration::from_millis(draws.below(profile.jitter_ms + 1));
        let arrival = schedule.arrival(
            &profile,
            direction.rate,
            epoch.elapsed(),
            read,
            jitter,
            lost,
        );
        if tx.send((epoch + arrival, buffer[..read].to_vec())).is_err() {
            break;
        }
    }
    drop(tx);
    let _ = deliver.await;
}

async fn deliver<W>(
    mut rx: mpsc::UnboundedReceiver<(Instant, Vec<u8>)>,
    mut to: W,
    room: Arc<Semaphore>,
    counters: Arc<Counters>,
    direction: Direction,
) where
    W: tokio::io::AsyncWrite + Unpin,
{
    while let Some((at, bytes)) = rx.recv().await {
        tokio::time::sleep_until(at).await;
        if to.write_all(&bytes).await.is_err() {
            break;
        }
        let total = if direction.down {
            &counters.down_bytes
        } else {
            &counters.up_bytes
        };
        total.fetch_add(bytes.len() as u64, Ordering::Relaxed);
        room.add_permits(bytes.len());
    }
    let _ = to.shutdown().await;
}

#[cfg(test)]
mod tests {
    use super::*;

    const ZERO: Duration = Duration::ZERO;

    fn ms(value: u64) -> Duration {
        Duration::from_millis(value)
    }

    fn schedule() -> Schedule {
        Schedule {
            free_at: ZERO,
            last_arrival: ZERO,
        }
    }

    #[test]
    fn capacity_and_delay_set_the_arrival() {
        // 1000 bytes on an 8 kbit/s link take one second, then 50 ms.
        let link = LinkProfile::clean("t", 8, 50);
        let mut s = schedule();
        assert_eq!(
            s.arrival(&link, link.down_bytes_per_s, ZERO, 1000, ZERO, false),
            ms(1050)
        );
        // The next chunk waits for the link, not for its own read time.
        assert_eq!(
            s.arrival(&link, link.down_bytes_per_s, ms(10), 500, ZERO, false),
            ms(1550)
        );
        // An idle link starts the next chunk when it is taken.
        assert_eq!(
            s.arrival(&link, link.down_bytes_per_s, ms(5000), 0, ZERO, false),
            ms(5050)
        );
    }

    #[test]
    fn jitter_and_loss_never_reorder_the_stream() {
        let link = LinkProfile {
            loss_stall_ms: 200,
            ..LinkProfile::clean("t", 100_000, 20)
        };
        let mut s = schedule();
        let late = s.arrival(&link, link.down_bytes_per_s, ZERO, 10, ms(40), false);
        let behind = s.arrival(&link, link.down_bytes_per_s, ms(1), 10, ZERO, false);
        assert!(behind >= late, "{behind:?} before {late:?}");
        let lost = s.arrival(&link, link.down_bytes_per_s, ms(100), 10, ZERO, true);
        assert!(lost >= ms(320));
        let next = s.arrival(&link, link.down_bytes_per_s, ms(101), 10, ZERO, false);
        assert_eq!(next, lost);
    }

    #[test]
    fn an_outage_holds_arrivals_until_it_ends() {
        let link = LinkProfile {
            outage_every_ms: 1000,
            outage_ms: 300,
            ..LinkProfile::clean("t", 100_000, 0)
        };
        let mut s = schedule();
        // The first period has no outage.
        assert!(s.arrival(&link, link.down_bytes_per_s, ms(100), 1, ZERO, false) < ms(101));
        let held = s.arrival(&link, link.down_bytes_per_s, ms(1100), 1, ZERO, false);
        assert_eq!(held, ms(1300));
        assert!(s.arrival(&link, link.down_bytes_per_s, ms(1500), 1, ZERO, false) < ms(1501));
    }

    #[test]
    fn malformed_profiles_are_refused() {
        let clean = LinkProfile::clean("t", 1000, 10);
        assert!(clean.validate().is_ok());
        for bad in [
            LinkProfile {
                down_bytes_per_s: 0,
                ..clean
            },
            LinkProfile {
                queue_bytes: 10,
                ..clean
            },
            LinkProfile {
                loss_per_mille: 1001,
                ..clean
            },
            LinkProfile {
                outage_every_ms: 100,
                outage_ms: 100,
                ..clean
            },
        ] {
            assert!(bad.validate().is_err(), "{bad:?}");
        }
    }

    #[tokio::test]
    async fn the_relay_carries_bytes_at_the_link_rate() {
        // An echo server behind a 400 kbit/s, 30 ms link: 20 KB down takes
        // about 400 ms plus the delay, and arrives intact.
        let echo = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let upstream = echo.local_addr().unwrap();
        let payload: Vec<u8> = (0..20_000u32).map(|i| (i % 251) as u8).collect();
        let sent = payload.clone();
        tokio::spawn(async move {
            let (mut socket, _) = echo.accept().await.unwrap();
            socket.write_all(&sent).await.unwrap();
            socket.shutdown().await.unwrap();
        });
        let link = LinkProfile::clean("t", 400, 30);
        let relay = start(upstream, link, 7).await.unwrap();
        let started = std::time::Instant::now();
        let mut client = TcpStream::connect(relay.addr).await.unwrap();
        let mut received = Vec::new();
        client.read_to_end(&mut received).await.unwrap();
        let took = started.elapsed();
        assert_eq!(received, payload);
        assert!(took >= ms(420), "{took:?}");
        assert!(took < ms(3000), "{took:?}");
        let report = relay.report();
        assert_eq!(report.connections, 1);
        assert_eq!(report.down_bytes, 20_000);
        relay.reset();
        assert_eq!(relay.report().down_bytes, 0);
    }

    #[tokio::test]
    async fn a_full_link_pushes_back_on_the_sender() {
        // A megabyte through a 1 MB/s link with an 8 KiB queue: the relay
        // spends most of that second refusing more bytes, and the reader
        // gets every byte no sooner than the link allows.
        let server = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let upstream = server.local_addr().unwrap();
        let link = LinkProfile {
            queue_bytes: 8 * 1024,
            ..LinkProfile::clean("t", 8_000, 0)
        };
        let relay = start(upstream, link, 9).await.unwrap();
        tokio::spawn(async move {
            let (mut socket, _) = server.accept().await.unwrap();
            socket.write_all(&vec![1u8; 1_000_000]).await.unwrap();
            socket.shutdown().await.unwrap();
        });
        let started = std::time::Instant::now();
        let mut client = TcpStream::connect(relay.addr).await.unwrap();
        let mut received = Vec::new();
        client.read_to_end(&mut received).await.unwrap();
        assert_eq!(received.len(), 1_000_000);
        assert!(started.elapsed() >= ms(950), "{:?}", started.elapsed());
        let report = relay.report();
        assert!(report.down_blocked_ms > 300.0, "{report:?}");
        assert!(report.down_peak_queue_bytes <= 8 * 1024, "{report:?}");
    }
}
