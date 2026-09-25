use crate::protocol::{ClientMessage, Role, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, watch, Mutex, Semaphore};
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::{accept_async_with_config, tungstenite::Message};
use uuid::Uuid;

type ServerSocket = tokio_tungstenite::WebSocketStream<TcpStream>;

/// Tracing target for the host's audit trail: joins, rejects, kicks and bans.
/// Never log a ticket, resume token or secret under it.
pub const AUDIT_TARGET: &str = "fragr_server::audit";

/// Owns the socket's write half. Sends queued messages and a ping on a fixed
/// cadence. Returns the sink so a kick can still send its reason and close.
async fn run_outbound_writer<S>(
    mut sink: S,
    mut rx: WsRx,
    shutdown: watch::Sender<bool>,
    send_timeout: Duration,
    ping_every: Duration,
    mut stop: tokio::sync::oneshot::Receiver<()>,
    traffic: Arc<crate::metrics::ClientTraffic>,
) -> S
where
    S: futures_util::Sink<Message> + Unpin,
{
    let mut ping = tokio::time::interval_at(tokio::time::Instant::now() + ping_every, ping_every);
    ping.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        let frame = tokio::select! {
            msg = rx.recv() => {
                let Some(msg) = msg else { break };
                let Ok(json) = serde_json::to_string(&msg) else {
                    tracing::warn!("Failed to serialize outbound server message; dropping client send");
                    break;
                };
                Message::Text(json)
            }
            _ = ping.tick() => Message::Ping(Vec::new()),
            _ = &mut stop => return sink,
        };
        let text_bytes = match &frame {
            Message::Text(text) => Some(text.len()),
            _ => None,
        };
        if !matches!(
            tokio::time::timeout(send_timeout, sink.send(frame)).await,
            Ok(Ok(()))
        ) {
            break;
        }
        if let Some(bytes) = text_bytes {
            traffic.sent(bytes);
        }
    }
    shutdown.send_replace(true);
    sink
}

/// One text frame is a hello, an action, or a short spoken line. 64 KiB is
/// far above that and far below the crate default of 64 MiB.
const MAX_MESSAGE_BYTES: usize = 64 * 1024;
const MAX_FRAME_BYTES: usize = 64 * 1024;
/// Must stay above tungstenite's 128 KiB write buffer. A full buffer drops the
/// slow reader instead of storing the match in memory.
const MAX_WRITE_BUFFER_BYTES: usize = 512 * 1024;
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
const HELLO_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_CONNECTIONS: usize = 64;
/// Sixteen agents plus the playtest observer share 127.0.0.1. A household
/// or a LAN behind one address needs that same headroom. The global cap
/// still stops one address from holding every slot.
const MAX_CONNECTIONS_PER_IP: usize = 32;
pub const OUTBOUND_QUEUE_CAPACITY: usize = 64;
const OUTBOUND_SEND_TIMEOUT: Duration = Duration::from_secs(2);
/// A displayed frame can send one action. 256 per second covers a fast
/// monitor. A tighter flood is dropped before it reaches the tick queue.
const INBOUND_PER_SEC: f32 = 256.0;
const INBOUND_BURST: f32 = 64.0;

/// The server pings every open session on this cadence. Every WebSocket
/// client answers a ping while it reads, so a quiet spectator stays live.
const PING_EVERY: Duration = Duration::from_secs(15);
/// No frame at all for this long, not even a pong, closes with `idle_timeout`.
/// Three missed pings, so one long frame hitch is not a disconnect.
const IDLE_AFTER: Duration = Duration::from_secs(45);
/// Dropped messages fill a strike level that drains at this rate. A client
/// that renders uncapped sends one action per frame, so only a sustained rate
/// far above any display (more than 4352 per second) grows the level.
const FLOOD_DRAIN_PER_SEC: f32 = 4096.0;
/// Past this level the session closes with `rate_limited`.
const FLOOD_LIMIT: f32 = 8192.0;
/// Unreadable frames: binary, or text that is not a JSON object with a string
/// `type`. One a second is forgiven. Sixteen more closes with `malformed`.
const JUNK_DRAIN_PER_SEC: f32 = 1.0;
const JUNK_LIMIT: f32 = 16.0;

/// Per-session liveness and conduct bounds. Tests shrink them.
#[derive(Debug, Clone, Copy)]
pub(crate) struct SessionLimits {
    pub ping_every: Duration,
    pub idle_after: Duration,
    pub flood_drain_per_sec: f32,
    pub flood_limit: f32,
    pub junk_drain_per_sec: f32,
    pub junk_limit: f32,
}

impl Default for SessionLimits {
    fn default() -> Self {
        Self {
            ping_every: PING_EVERY,
            idle_after: IDLE_AFTER,
            flood_drain_per_sec: FLOOD_DRAIN_PER_SEC,
            flood_limit: FLOOD_LIMIT,
            junk_drain_per_sec: JUNK_DRAIN_PER_SEC,
            junk_limit: JUNK_LIMIT,
        }
    }
}

/// A leaky counter. Strikes add, time drains, and past the limit it trips.
#[derive(Debug)]
struct Strikes {
    level: f32,
    updated: std::time::Instant,
}

impl Strikes {
    fn new(now: std::time::Instant) -> Self {
        Self {
            level: 0.0,
            updated: now,
        }
    }

    fn add(&mut self, now: std::time::Instant, drain_per_sec: f32, limit: f32) -> bool {
        let elapsed = now.saturating_duration_since(self.updated).as_secs_f32();
        self.updated = now;
        self.level = (self.level - elapsed * drain_per_sec).max(0.0) + 1.0;
        self.level > limit
    }
}

/// Why the server ended a live session. Each has a stable wire code.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Kick {
    Idle,
    RateLimited,
    Malformed,
    Refused(crate::access::Verdict),
}

impl Kick {
    fn code(&self) -> &'static str {
        match self {
            Kick::Idle => "idle_timeout",
            Kick::RateLimited => "rate_limited",
            Kick::Malformed => "malformed",
            Kick::Refused(verdict) => verdict.code().unwrap_or("address_banned"),
        }
    }

    fn message(&self) -> &'static str {
        match self {
            Kick::Idle => "No reply from this client. Connection closed.",
            Kick::RateLimited => "Too many messages. Connection closed.",
            Kick::Malformed => "Unreadable messages. Connection closed.",
            Kick::Refused(_) => refusal_message(self.code()),
        }
    }

    /// Only a silent network keeps a resumable pawn. Abuse and bans remove it.
    fn removes_pawn(&self) -> bool {
        !matches!(self, Kick::Idle)
    }

    fn audit_event(&self) -> &'static str {
        match self {
            Kick::Refused(crate::access::Verdict::Banned { .. }) => "ban",
            _ => "kick",
        }
    }
}

fn refusal_message(code: &str) -> &'static str {
    match code {
        "address_limit" => "Too many connections from this address.",
        "address_banned" => "This server does not accept connections from this address.",
        "address_not_allowed" => "This server only accepts listed addresses.",
        _ => "This server is not taking more connections.",
    }
}

/// Text that is not even a JSON object with a string `type`. A well-formed
/// message of a type this server does not know is ignored, not junk, so a
/// newer client is never closed for it.
fn is_junk(text: &str) -> bool {
    match serde_json::from_str::<serde_json::Value>(text) {
        Ok(serde_json::Value::Object(map)) => {
            !matches!(map.get("type"), Some(serde_json::Value::String(_)))
        }
        _ => true,
    }
}

/// Callsigns come from the client. Bound and escape them for the log.
fn audit_name(name: &str) -> String {
    name.chars().take(32).collect()
}

fn audit_reject(peer: std::net::SocketAddr, code: &str) {
    tracing::info!(target: AUDIT_TARGET, event = "reject", peer = %peer, code);
}

struct InboundBudget {
    tokens: f32,
    updated: std::time::Instant,
}

impl InboundBudget {
    fn new() -> Self {
        Self {
            tokens: INBOUND_BURST,
            updated: std::time::Instant::now(),
        }
    }

    fn allow(&mut self) -> bool {
        let now = std::time::Instant::now();
        let elapsed = now.saturating_duration_since(self.updated).as_secs_f32();
        self.updated = now;
        self.tokens = (self.tokens + elapsed * INBOUND_PER_SEC).min(INBOUND_BURST);
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

fn websocket_limits() -> WebSocketConfig {
    #[allow(deprecated)]
    WebSocketConfig {
        max_message_size: Some(MAX_MESSAGE_BYTES),
        max_frame_size: Some(MAX_FRAME_BYTES),
        max_write_buffer_size: MAX_WRITE_BUFFER_BYTES,
        ..WebSocketConfig::default()
    }
}

struct Admission {
    global: Arc<Semaphore>,
    per_ip: std::sync::Arc<std::sync::Mutex<HashMap<IpAddr, usize>>>,
    max_per_ip: usize,
    handshake_timeout: Duration,
    hello_timeout: Duration,
    limits: SessionLimits,
}

struct AdmissionPermit {
    ip: IpAddr,
    per_ip: std::sync::Arc<std::sync::Mutex<HashMap<IpAddr, usize>>>,
    _global: tokio::sync::OwnedSemaphorePermit,
}

impl Drop for AdmissionPermit {
    fn drop(&mut self) {
        let mut counts = self
            .per_ip
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if let Some(count) = counts.get_mut(&self.ip) {
            *count = count.saturating_sub(1);
            if *count == 0 {
                counts.remove(&self.ip);
            }
        }
    }
}

impl Admission {
    fn standard() -> Self {
        Self::new(
            MAX_CONNECTIONS,
            MAX_CONNECTIONS_PER_IP,
            HANDSHAKE_TIMEOUT,
            HELLO_TIMEOUT,
        )
    }

    fn new(
        max_connections: usize,
        max_per_ip: usize,
        handshake_timeout: Duration,
        hello_timeout: Duration,
    ) -> Self {
        Self {
            global: Arc::new(Semaphore::new(max_connections.max(1))),
            per_ip: std::sync::Arc::new(std::sync::Mutex::new(HashMap::new())),
            max_per_ip: max_per_ip.max(1),
            handshake_timeout,
            hello_timeout,
            limits: SessionLimits::default(),
        }
    }

    fn try_admit(self: &std::sync::Arc<Self>, ip: IpAddr) -> Result<AdmissionPermit, &'static str> {
        let global = Arc::clone(&self.global)
            .try_acquire_owned()
            .map_err(|_| "connection_limit")?;
        let mut counts = self
            .per_ip
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let count = counts.entry(ip).or_insert(0);
        if *count >= self.max_per_ip {
            return Err("address_limit");
        }
        *count += 1;
        Ok(AdmissionPermit {
            ip,
            per_ip: std::sync::Arc::clone(&self.per_ip),
            _global: global,
        })
    }
}

/// Refuse a hello: audit it, then send the reason and close.
async fn reject_connection(
    sink: futures_util::stream::SplitSink<ServerSocket, Message>,
    stream: futures_util::stream::SplitStream<ServerSocket>,
    rejection: ServerMessage,
    peer: std::net::SocketAddr,
) -> Result<(), Box<dyn std::error::Error>> {
    if let ServerMessage::Error { code, .. } = &rejection {
        audit_reject(peer, code);
    }
    close_with_error(sink, stream, rejection).await
}

/// Complete the close handshake before dropping TCP, so a client polling less
/// often than the server can still read its admission error. Bound silent peers.
async fn close_with_error(
    mut sink: futures_util::stream::SplitSink<ServerSocket, Message>,
    mut stream: futures_util::stream::SplitStream<ServerSocket>,
    rejection: ServerMessage,
) -> Result<(), Box<dyn std::error::Error>> {
    let reason = match &rejection {
        ServerMessage::Error { code, .. } => code.clone(),
        _ => return Err("admission rejection must be an error".into()),
    };
    sink.send(Message::Text(serde_json::to_string(&rejection)?))
        .await?;
    // Some clients retire queued text when a close arrives in the same poll.
    // The stable code also survives in the protocol's bounded close reason.
    sink.send(Message::Close(Some(
        tokio_tungstenite::tungstenite::protocol::CloseFrame {
            code: tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode::Policy,
            reason: reason.into(),
        },
    )))
    .await?;
    let _ = tokio::time::timeout(std::time::Duration::from_secs(2), async {
        while let Some(Ok(message)) = stream.next().await {
            if message.is_close() {
                break;
            }
        }
    })
    .await;
    Ok(())
}

#[cfg(test)]
mod tests;

pub type WsTx = mpsc::Sender<ServerMessage>;
pub type WsRx = mpsc::Receiver<ServerMessage>;

pub struct ClientSession {
    pub id: Uuid,
    pub tx: WsTx,
    pub(crate) gameplay_version: u32,
    /// Broadcasts must follow the initial targeted geometry in this queue.
    pub(crate) initialized: bool,
    shutdown: watch::Sender<bool>,
    traffic: Arc<crate::metrics::ClientTraffic>,
}

impl ClientSession {
    /// A session outside the listener, for tests: its traffic is its own.
    pub fn new(id: Uuid, tx: WsTx, gameplay_version: u32) -> Self {
        let (shutdown, _) = watch::channel(false);
        let traffic = crate::metrics::ClientTraffic::new(Role::Spectator, Arc::default());
        Self::with_shutdown(id, tx, gameplay_version, shutdown, traffic)
    }

    fn with_shutdown(
        id: Uuid,
        tx: WsTx,
        gameplay_version: u32,
        shutdown: watch::Sender<bool>,
        traffic: Arc<crate::metrics::ClientTraffic>,
    ) -> Self {
        Self {
            id,
            tx,
            gameplay_version,
            initialized: false,
            shutdown,
            traffic,
        }
    }

    pub(crate) fn traffic(&self) -> &crate::metrics::ClientTraffic {
        &self.traffic
    }

    pub(crate) fn request_close(&self) {
        self.shutdown.send_replace(true);
    }

    pub(crate) fn queue_depth(&self) -> usize {
        self.tx.max_capacity().saturating_sub(self.tx.capacity())
    }

    pub(crate) fn is_closing(&self) -> bool {
        *self.shutdown.borrow()
    }
}

pub struct NetServer {
    listener: TcpListener,
    pub clients: Arc<Mutex<Vec<ClientSession>>>,
    game_tx: mpsc::UnboundedSender<GameCommand>,
    geometry_version: u32,
    gameplay_version: u32,
    party_slots: Option<Arc<Semaphore>>,
    solo_run: bool,
    admission: Arc<Admission>,
    status: Arc<tokio::sync::RwLock<crate::protocol::LiveStatus>>,
    join_secret: Option<std::sync::Arc<crate::join_ticket::JoinSecret>>,
    resume: std::sync::Arc<crate::resume::ResumeTable>,
    access: Option<AccessWatch>,
    traffic: Arc<crate::metrics::TrafficCounters>,
}

type AccessWatch = watch::Receiver<Arc<crate::access::AccessPolicy>>;

pub enum GameCommand {
    Connected {
        id: Uuid,
        role: Role,
        name: String,
        player_id: Option<Uuid>,
    },
    Disconnected {
        id: Uuid,
    },
    Action {
        player_id: Uuid,
        action: crate::protocol::Action,
    },
    MissionReady {
        player_id: Uuid,
        ready: crate::protocol::MissionReady,
    },
    MissionContinue {
        player_id: Uuid,
        request: crate::protocol::MissionContinue,
    },
    Speak {
        player_id: Uuid,
        text: String,
    },
    SetDisplayBehavior {
        player_id: Uuid,
        behavior: String,
    },
    /// The socket died. The pawn stays until grace or an explicit leave.
    Detached {
        id: Uuid,
    },
    /// Bind an existing parked pawn. The session answers on `reply`.
    Resume {
        client_id: Uuid,
        player_id: Uuid,
        nonce: u64,
        role: Role,
        reply: tokio::sync::oneshot::Sender<Option<crate::resume::ResumeAccept>>,
    },
}

impl NetServer {
    pub async fn bind(
        addr: &str,
        game_tx: mpsc::UnboundedSender<GameCommand>,
    ) -> std::io::Result<Self> {
        Self::bind_with_geometry(addr, game_tx, crate::protocol::legacy_geometry_version()).await
    }

    pub async fn bind_with_geometry(
        addr: &str,
        game_tx: mpsc::UnboundedSender<GameCommand>,
        geometry_version: u32,
    ) -> std::io::Result<Self> {
        Self::bind_with_requirements(addr, game_tx, geometry_version, 1).await
    }

    pub async fn bind_with_requirements(
        addr: &str,
        game_tx: mpsc::UnboundedSender<GameCommand>,
        geometry_version: u32,
        gameplay_version: u32,
    ) -> std::io::Result<Self> {
        if !(1..=crate::protocol::GAMEPLAY_VERSION).contains(&gameplay_version) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "unsupported server gameplay version",
            ));
        }
        if !(1..=crate::protocol::GEOMETRY_VERSION).contains(&geometry_version) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "unsupported server geometry version",
            ));
        }
        let listener = TcpListener::bind(addr).await?;
        tracing::info!("WebSocket server listening on {}", addr);

        Ok(Self {
            listener,
            clients: Arc::new(Mutex::new(Vec::new())),
            game_tx,
            geometry_version,
            gameplay_version,
            solo_run: false,
            party_slots: (gameplay_version >= crate::protocol::MISSION_GAMEPLAY_VERSION)
                .then(|| Arc::new(Semaphore::new(crate::protocol::MISSION_PARTY_LIMIT))),
            admission: Arc::new(Admission::standard()),
            status: Arc::new(tokio::sync::RwLock::new(
                crate::protocol::LiveStatus::default(),
            )),
            join_secret: None,
            resume: std::sync::Arc::new(crate::resume::ResumeTable::new()),
            access: None,
            traffic: Arc::default(),
        })
    }

    /// Refuse listed addresses before a slot or seat, and close live sessions
    /// whose address a later edit bans.
    pub fn set_access(&mut self, access: AccessWatch) {
        self.access = Some(access);
    }

    pub(crate) fn share_resume(&mut self, resume: std::sync::Arc<crate::resume::ResumeTable>) {
        self.resume = resume;
    }

    pub(crate) fn set_join_secret(
        &mut self,
        secret: std::sync::Arc<crate::join_ticket::JoinSecret>,
    ) {
        self.join_secret = Some(secret);
    }

    /// Payload totals for every session this listener admits, closed ones included.
    pub fn traffic_totals(&self) -> Arc<crate::metrics::TrafficCounters> {
        Arc::clone(&self.traffic)
    }

    /// Share the match line the tick loop refreshes. `GET /status` reads it.
    pub fn share_status(&mut self, status: Arc<tokio::sync::RwLock<crate::protocol::LiveStatus>>) {
        self.status = status;
    }

    /// Shrink the public caps for a test. Call it before `accept_loop`.
    #[cfg(test)]
    pub(crate) fn tighten_admission(
        &mut self,
        max_connections: usize,
        max_per_ip: usize,
        handshake_timeout: Duration,
        hello_timeout: Duration,
    ) {
        self.admission = Arc::new(Admission::new(
            max_connections,
            max_per_ip,
            handshake_timeout,
            hello_timeout,
        ));
    }

    /// Shrink liveness and conduct bounds for a test. Call it after
    /// `tighten_admission` and before `accept_loop`.
    #[cfg(test)]
    pub(crate) fn tighten_session(&mut self, limits: SessionLimits) {
        let admission = &self.admission;
        let mut replacement = Admission::new(
            admission.global.available_permits(),
            admission.max_per_ip,
            admission.handshake_timeout,
            admission.hello_timeout,
        );
        replacement.limits = limits;
        self.admission = Arc::new(replacement);
    }

    pub fn local_addr(&self) -> std::io::Result<std::net::SocketAddr> {
        self.listener.local_addr()
    }

    /// Only a completed admission consumes the run's lifetime combat seat.
    pub(crate) fn reserve_solo_run(&mut self) -> std::io::Result<()> {
        if self.gameplay_version < crate::protocol::CONTINUES_GAMEPLAY_VERSION {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "solo run requires continue capability",
            ));
        }
        self.solo_run = true;
        self.party_slots = Some(Arc::new(Semaphore::new(1)));
        Ok(())
    }

    pub async fn accept_loop(self) {
        loop {
            match self.listener.accept().await {
                Ok((mut stream, addr)) => {
                    tracing::debug!("New connection from {}", addr);
                    let game_tx = self.game_tx.clone();
                    let clients = self.clients.clone();
                    let geometry_version = self.geometry_version;
                    let gameplay_version = self.gameplay_version;
                    let party_slots = self.party_slots.clone();
                    let solo_run = self.solo_run;
                    let admission = Arc::clone(&self.admission);
                    let status = Arc::clone(&self.status);
                    let handshake_timeout = admission.handshake_timeout;
                    let hello_timeout = admission.hello_timeout;
                    let join_secret = self.join_secret.clone();
                    let resume_table = std::sync::Arc::clone(&self.resume);
                    let access = self.access.clone();
                    let traffic = Arc::clone(&self.traffic);

                    tokio::spawn(async move {
                        let verdict =
                            access
                                .as_ref()
                                .map_or(crate::access::Verdict::Admit, |policy| {
                                    policy
                                        .borrow()
                                        .check(addr.ip(), crate::join_ticket::unix_now())
                                });
                        if let Some(code) = verdict.code() {
                            audit_refusal(addr, &verdict);
                            // The explanation holds a slot, so a refused flood stays
                            // inside the connection caps. Past them, just drop TCP.
                            if let Ok(_permit) = admission.try_admit(addr.ip()) {
                                reject_before_hello(stream, code, handshake_timeout).await;
                            }
                            return;
                        }
                        if serve_status_if_requested(&mut stream, &status).await {
                            return;
                        }
                        let permit = match admission.try_admit(addr.ip()) {
                            Ok(permit) => permit,
                            Err(code) => {
                                audit_reject(addr, code);
                                reject_before_hello(stream, code, handshake_timeout).await;
                                return;
                            }
                        };
                        let limits = admission.limits;
                        if let Err(e) = handle_connection(
                            stream,
                            game_tx,
                            clients,
                            HelloPolicy {
                                required_geometry: geometry_version,
                                required_gameplay: gameplay_version,
                                party_slots,
                                solo_run,
                                handshake_timeout,
                                hello_timeout,
                                join_secret,
                                resume: resume_table,
                                peer: addr,
                                access,
                                limits,
                                traffic,
                            },
                        )
                        .await
                        {
                            tracing::warn!("Connection error: {}", e);
                        }
                        drop(permit);
                    });
                }
                Err(e) => {
                    tracing::error!("Accept error: {}", e);
                }
            }
        }
    }
}

fn is_status_request(buf: &[u8]) -> bool {
    const PREFIX: &[u8] = b"GET /status";
    if !buf.starts_with(PREFIX) {
        return false;
    }
    matches!(buf.get(PREFIX.len()), Some(b' ' | b'?' | b'\r' | b'\n'))
}

/// `Some(true)` once the bytes are a status GET. `Some(false)` once they are
/// anything else. `None` while the first line is still too short to tell.
fn classify_opening(buf: &[u8]) -> Option<bool> {
    if buf.len() < 4 {
        return None;
    }
    if !buf.starts_with(b"GET ") {
        return Some(false);
    }
    if buf.len() < b"GET /status".len() {
        return None;
    }
    Some(is_status_request(buf))
}

async fn serve_status_if_requested(
    stream: &mut TcpStream,
    status: &tokio::sync::RwLock<crate::protocol::LiveStatus>,
) -> bool {
    let mut buf = [0u8; 24];
    let mut seen = 0usize;
    let deadline = tokio::time::Instant::now() + Duration::from_millis(300);
    let mut status_get = false;
    while tokio::time::Instant::now() < deadline {
        match tokio::time::timeout(Duration::from_millis(50), stream.peek(&mut buf)).await {
            Ok(Ok(n)) if n > seen => {
                seen = n;
                match classify_opening(&buf[..seen]) {
                    Some(true) => {
                        status_get = true;
                        break;
                    }
                    Some(false) => return false,
                    None => tokio::time::sleep(Duration::from_millis(10)).await,
                }
            }
            Ok(Ok(_)) => tokio::time::sleep(Duration::from_millis(10)).await,
            _ => break,
        }
    }
    if !status_get {
        return false;
    }
    let mut header = Vec::with_capacity(256);
    let mut tmp = [0u8; 256];
    let read_deadline = tokio::time::Instant::now() + Duration::from_secs(1);
    while tokio::time::Instant::now() < read_deadline && header.len() < 2048 {
        let n = match tokio::time::timeout(Duration::from_millis(200), stream.read(&mut tmp)).await
        {
            Ok(Ok(0)) | Err(_) => break,
            Ok(Ok(n)) => n,
            Ok(Err(_)) => break,
        };
        header.extend_from_slice(&tmp[..n]);
        if header.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
    }
    let with_clients = crate::metrics::wants_clients(&header);
    let body = match status.try_read() {
        Ok(live) => serde_json::to_string(&crate::metrics::served_status(
            &live,
            with_clients,
            crate::metrics::process_uptime(),
        ))
        .unwrap_or_else(|_| "{}".into()),
        Err(_) => "{\"schema_version\":1}".into(),
    };
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n{body}",
        body.len()
    );
    let _ = stream.write_all(response.as_bytes()).await;
    let _ = stream.shutdown().await;
    true
}

async fn reject_before_hello(stream: TcpStream, code: &str, handshake_timeout: Duration) {
    let accepted = tokio::time::timeout(
        handshake_timeout,
        accept_async_with_config(stream, Some(websocket_limits())),
    )
    .await;
    let Ok(Ok(ws)) = accepted else {
        return;
    };
    let (sink, stream) = ws.split();
    let _ = close_with_error(
        sink,
        stream,
        ServerMessage::Error {
            code: code.into(),
            message: refusal_message(code).into(),
        },
    )
    .await;
}

fn audit_refusal(peer: std::net::SocketAddr, verdict: &crate::access::Verdict) {
    match verdict {
        crate::access::Verdict::Banned { line, reason } => tracing::info!(
            target: AUDIT_TARGET,
            event = "ban",
            peer = %peer,
            code = "address_banned",
            list_line = line,
            reason = ?reason,
        ),
        other => audit_reject(peer, other.code().unwrap_or("address_not_allowed")),
    }
}

struct HelloPolicy {
    required_geometry: u32,
    required_gameplay: u32,
    party_slots: Option<Arc<Semaphore>>,
    solo_run: bool,
    handshake_timeout: Duration,
    hello_timeout: Duration,
    join_secret: Option<std::sync::Arc<crate::join_ticket::JoinSecret>>,
    resume: std::sync::Arc<crate::resume::ResumeTable>,
    peer: std::net::SocketAddr,
    access: Option<AccessWatch>,
    limits: SessionLimits,
    traffic: Arc<crate::metrics::TrafficCounters>,
}

/// What the reader loop learned about the session as it ended.
struct SessionEnd {
    left: bool,
    kick: Option<Kick>,
}

/// Read one admitted session until it closes, leaves, goes silent, or is
/// kicked. Every frame, including a pong, proves the client is still there.
async fn read_session(
    ws_stream: &mut futures_util::stream::SplitStream<ServerSocket>,
    shutdown_rx: &mut watch::Receiver<bool>,
    game_tx: &mpsc::UnboundedSender<GameCommand>,
    role: Role,
    player_id: Option<Uuid>,
    policy: &HelloPolicy,
    traffic: &crate::metrics::ClientTraffic,
) -> SessionEnd {
    let limits = policy.limits;
    let mut inbound = InboundBudget::new();
    let started = std::time::Instant::now();
    let mut flood = Strikes::new(started);
    let mut junk = Strikes::new(started);
    let mut access = policy.access.clone();
    if let Some(watcher) = access.as_mut() {
        watcher.mark_unchanged();
    }
    let idle = tokio::time::sleep(limits.idle_after);
    tokio::pin!(idle);
    let mut left = false;
    let kick = loop {
        let msg = tokio::select! {
            msg = ws_stream.next() => msg,
            changed = shutdown_rx.changed() => {
                if changed.is_err() || *shutdown_rx.borrow_and_update() {
                    break None;
                }
                continue;
            }
            () = &mut idle => break Some(Kick::Idle),
            changed = async {
                match access.as_mut() {
                    Some(watcher) => watcher.changed().await,
                    None => std::future::pending().await,
                }
            } => {
                let Some(watcher) = access.as_mut().filter(|_| changed.is_ok()) else {
                    access = None;
                    continue;
                };
                let verdict = watcher
                    .borrow_and_update()
                    .check(policy.peer.ip(), crate::join_ticket::unix_now());
                if verdict.code().is_some() {
                    break Some(Kick::Refused(verdict));
                }
                continue;
            }
        };
        let Some(msg) = msg else {
            break None;
        };
        let text = match msg {
            Ok(Message::Close(_)) | Err(_) => break None,
            Ok(frame) => {
                idle.as_mut()
                    .reset(tokio::time::Instant::now() + limits.idle_after);
                match frame {
                    Message::Text(text) => {
                        traffic.received(text.len());
                        Some(text)
                    }
                    Message::Binary(bytes) => {
                        traffic.received(bytes.len());
                        None
                    }
                    _ => continue,
                }
            }
        };
        let now = std::time::Instant::now();
        if !inbound.allow() {
            if flood.add(now, limits.flood_drain_per_sec, limits.flood_limit) {
                break Some(Kick::RateLimited);
            }
            continue;
        }
        let Some(text) = text else {
            if junk.add(now, limits.junk_drain_per_sec, limits.junk_limit) {
                break Some(Kick::Malformed);
            }
            continue;
        };
        let message = match serde_json::from_str::<ClientMessage>(&text) {
            Ok(message) => message,
            Err(_) => {
                if is_junk(&text) && junk.add(now, limits.junk_drain_per_sec, limits.junk_limit) {
                    break Some(Kick::Malformed);
                }
                continue;
            }
        };
        if matches!(message, ClientMessage::Leave) {
            left = true;
            continue;
        }
        let Some(player_id) = player_id.filter(|_| role != Role::Spectator) else {
            continue;
        };
        let command = match message {
            ClientMessage::Action(action) => GameCommand::Action { player_id, action },
            ClientMessage::MissionReady(ready) => GameCommand::MissionReady { player_id, ready },
            ClientMessage::MissionContinue(request) => {
                GameCommand::MissionContinue { player_id, request }
            }
            ClientMessage::Speak(speak) => GameCommand::Speak {
                player_id,
                text: speak.text,
            },
            // Further gated in sim (rule bots / humans ignored).
            ClientMessage::SetDisplayBehavior(msg) if role == Role::Agent => {
                GameCommand::SetDisplayBehavior {
                    player_id,
                    behavior: msg.behavior,
                }
            }
            _ => continue,
        };
        let _ = game_tx.send(command);
    };
    SessionEnd { left, kick }
}

async fn send_welcome(
    sink: &mut futures_util::stream::SplitSink<ServerSocket, Message>,
    welcome: &ServerMessage,
    traffic: &crate::metrics::ClientTraffic,
) -> Result<(), Box<dyn std::error::Error>> {
    let text = serde_json::to_string(welcome)?;
    let bytes = text.len();
    sink.send(Message::Text(text)).await?;
    traffic.sent(bytes);
    Ok(())
}

async fn handle_connection(
    stream: TcpStream,
    game_tx: mpsc::UnboundedSender<GameCommand>,
    clients: Arc<Mutex<Vec<ClientSession>>>,
    policy: HelloPolicy,
) -> Result<(), Box<dyn std::error::Error>> {
    let peer = policy.peer;
    let ws_stream = match tokio::time::timeout(
        policy.handshake_timeout,
        accept_async_with_config(stream, Some(websocket_limits())),
    )
    .await
    {
        Ok(Ok(stream)) => stream,
        Ok(Err(error)) => return Err(error.into()),
        Err(_) => {
            audit_reject(peer, "handshake_timeout");
            return Ok(());
        }
    };
    let (mut ws_sink, mut ws_stream) = ws_stream.split();

    let (tx, rx): (WsTx, WsRx) = mpsc::channel(OUTBOUND_QUEUE_CAPACITY);
    let (shutdown_tx, mut shutdown_rx) = watch::channel(false);
    let client_id = Uuid::new_v4();

    let role;
    let player_id;
    let traffic;
    // RAII returns seats after failed admission and development-party disconnect.
    // Solo admission consumes its permit for the server lifetime below.
    // A resume request parks the seat instead of returning it on a drop.
    let mut _party_seat;
    let mut keep_pawn = false;

    let first = match tokio::time::timeout(policy.hello_timeout, ws_stream.next()).await {
        Ok(message) => message,
        Err(_) => {
            audit_reject(peer, "hello_timeout");
            return Ok(());
        }
    };
    if let Some(Ok(Message::Text(text))) = first {
        match serde_json::from_str::<ClientMessage>(&text) {
            Ok(ClientMessage::Hello {
                role: r,
                name,
                geometry_version,
                gameplay_version,
                ticket,
                resume,
            }) => {
                if !crate::join_ticket::admit(
                    policy.join_secret.as_deref(),
                    r,
                    ticket.as_deref(),
                    crate::join_ticket::unix_now(),
                ) {
                    let rejection = ServerMessage::Error {
                        code: "join_rejected".into(),
                        message: "This server refused the join.".into(),
                    };
                    return reject_connection(ws_sink, ws_stream, rejection, peer).await;
                }
                if gameplay_version < policy.required_gameplay {
                    let rejection = ServerMessage::Error {
                        code: "unsupported_gameplay".into(),
                        message: format!(
                            "This server requires gameplay version {}; update your client.",
                            policy.required_gameplay
                        ),
                    };
                    return reject_connection(ws_sink, ws_stream, rejection, peer).await;
                }
                if geometry_version < policy.required_geometry {
                    let rejection = ServerMessage::Error {
                        code: "unsupported_geometry".into(),
                        message: format!(
                            "This server requires geometry version {}; update your client.",
                            policy.required_geometry
                        ),
                    };
                    return reject_connection(ws_sink, ws_stream, rejection, peer).await;
                }
                traffic = crate::metrics::ClientTraffic::new(r, Arc::clone(&policy.traffic));
                traffic.received(text.len());
                let resume_rejected = || ServerMessage::Error {
                    code: "resume_rejected".into(),
                    message: "The previous pawn is gone.".into(),
                };
                let mut resumed: Option<crate::resume::ResumeAccept> = None;
                if r != Role::Spectator {
                    if let Some(token) = resume.as_deref().filter(|token| !token.is_empty()) {
                        let Some((claimed_id, claimed_role, nonce)) = policy.resume.open(token)
                        else {
                            return reject_connection(ws_sink, ws_stream, resume_rejected(), peer)
                                .await;
                        };
                        if claimed_role != r {
                            return reject_connection(ws_sink, ws_stream, resume_rejected(), peer)
                                .await;
                        }
                        let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
                        clients.lock().await.push(ClientSession::with_shutdown(
                            client_id,
                            tx.clone(),
                            gameplay_version,
                            shutdown_tx.clone(),
                            Arc::clone(&traffic),
                        ));
                        if game_tx
                            .send(GameCommand::Resume {
                                client_id,
                                player_id: claimed_id,
                                nonce,
                                role: r,
                                reply: reply_tx,
                            })
                            .is_err()
                        {
                            clients.lock().await.retain(|client| client.id != client_id);
                            return Ok(());
                        }
                        resumed = tokio::time::timeout(std::time::Duration::from_secs(2), reply_rx)
                            .await
                            .ok()
                            .and_then(Result::ok)
                            .flatten();
                        if resumed.is_none() {
                            clients.lock().await.retain(|client| client.id != client_id);
                            return reject_connection(ws_sink, ws_stream, resume_rejected(), peer)
                                .await;
                        }
                    }
                }
                if let Some(accepted) = resumed {
                    player_id = Some(accepted.player_id);
                    _party_seat = accepted.seat;
                    role = Some(r);
                    keep_pawn = true;
                    let welcome = ServerMessage::Welcome {
                        player_id,
                        role: r,
                        mode_name: crate::protocol::default_mode_name(),
                        playlist: crate::protocol::default_playlist(),
                        resume: Some(accepted.token),
                    };
                    send_welcome(&mut ws_sink, &welcome, &traffic).await?;
                    tracing::info!(
                        target: AUDIT_TARGET,
                        event = "resume",
                        peer = %peer,
                        client = %client_id,
                        role = ?r,
                        player = ?player_id,
                        name = ?audit_name(&name),
                    );
                } else {
                    _party_seat = if r != Role::Spectator {
                        match policy.party_slots {
                            Some(ref slots) => match Arc::clone(slots).try_acquire_owned() {
                                Ok(seat) => Some(seat),
                                Err(_) => {
                                    let rejection = ServerMessage::Error {
                                    code: if policy.solo_run { "run_seat_closed" } else { "party_full" }.into(),
                                    message: if policy.solo_run {
                                        "This run already has an owner. Join as a spectator or start a new run."
                                    } else {
                                        "This mission supports four participants; join as a spectator or wait for a seat."
                                    }.into(),
                                };
                                    return reject_connection(ws_sink, ws_stream, rejection, peer)
                                        .await;
                                }
                            },
                            None => None,
                        }
                    } else {
                        None
                    };
                    role = Some(r);

                    player_id = if r != Role::Spectator {
                        Some(Uuid::new_v4())
                    } else {
                        None
                    };
                    let issued = if r != Role::Spectator && resume.is_some() {
                        keep_pawn = true;
                        player_id.map(|id| policy.resume.arm(id, r))
                    } else {
                        None
                    };

                    let welcome = ServerMessage::Welcome {
                        player_id,
                        role: r,
                        mode_name: crate::protocol::default_mode_name(),
                        playlist: crate::protocol::default_playlist(),
                        resume: issued,
                    };

                    send_welcome(&mut ws_sink, &welcome, &traffic).await?;

                    let mut clients_lock = clients.lock().await;
                    clients_lock.push(ClientSession::with_shutdown(
                        client_id,
                        tx.clone(),
                        gameplay_version,
                        shutdown_tx.clone(),
                        Arc::clone(&traffic),
                    ));
                    drop(clients_lock);

                    let logged_name = audit_name(&name);
                    game_tx.send(GameCommand::Connected {
                        id: client_id,
                        role: r,
                        name,
                        player_id,
                    })?;
                    if policy.solo_run {
                        if let Some(seat) = _party_seat.take() {
                            seat.forget();
                        }
                    }

                    tracing::info!(
                        target: AUDIT_TARGET,
                        event = "join",
                        peer = %peer,
                        client = %client_id,
                        role = ?r,
                        player = ?player_id,
                        name = ?logged_name,
                    );
                }
            }
            _ => {
                audit_reject(peer, "bad_hello");
                return Ok(());
            }
        }
    } else {
        audit_reject(peer, "bad_hello");
        return Ok(());
    }

    let role = role.unwrap();

    let (stop_writer, writer_stop) = tokio::sync::oneshot::channel();
    let mut send_task = tokio::spawn(run_outbound_writer(
        ws_sink,
        rx,
        shutdown_tx,
        OUTBOUND_SEND_TIMEOUT,
        policy.limits.ping_every,
        writer_stop,
        Arc::clone(&traffic),
    ));

    let end = read_session(
        &mut ws_stream,
        &mut shutdown_rx,
        &game_tx,
        role,
        player_id,
        &policy,
        &traffic,
    )
    .await;

    // A kick takes the write half back to send its reason. A stalled writer
    // gives up within its own send timeout.
    let sink = if end.kick.is_some() {
        let _ = stop_writer.send(());
        match tokio::time::timeout(
            OUTBOUND_SEND_TIMEOUT + Duration::from_millis(500),
            &mut send_task,
        )
        .await
        {
            Ok(Ok(sink)) => Some(sink),
            _ => {
                send_task.abort();
                None
            }
        }
    } else {
        send_task.abort();
        None
    };

    let removes_pawn = end.left || end.kick.as_ref().is_some_and(Kick::removes_pawn);
    if let Some(pid) = player_id {
        if keep_pawn && !removes_pawn {
            policy
                .resume
                .park(pid, _party_seat.take(), policy.resume.tick());
            let _ = game_tx.send(GameCommand::Detached { id: client_id });
        } else {
            policy.resume.forget(pid);
            let _ = game_tx.send(GameCommand::Disconnected { id: client_id });
        }
    } else {
        let _ = game_tx.send(GameCommand::Disconnected { id: client_id });
    }

    let mut clients_lock = clients.lock().await;
    clients_lock.retain(|c| c.id != client_id);
    drop(clients_lock);

    if let Some(kick) = end.kick {
        tracing::info!(
            target: AUDIT_TARGET,
            event = kick.audit_event(),
            peer = %peer,
            client = %client_id,
            role = ?role,
            player = ?player_id,
            code = kick.code(),
        );
        if let Some(sink) = sink {
            let reason = ServerMessage::Error {
                code: kick.code().into(),
                message: kick.message().into(),
            };
            let _ = tokio::time::timeout(
                Duration::from_secs(3),
                close_with_error(sink, ws_stream, reason),
            )
            .await;
        }
    }

    tracing::info!("Client {:?} disconnected", client_id);

    Ok(())
}
