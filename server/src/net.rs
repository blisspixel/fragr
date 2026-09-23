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

async fn run_outbound_writer<S>(
    mut sink: S,
    mut rx: WsRx,
    shutdown: watch::Sender<bool>,
    send_timeout: Duration,
) where
    S: futures_util::Sink<Message> + Unpin,
{
    while let Some(msg) = rx.recv().await {
        let Ok(json) = serde_json::to_string(&msg) else {
            tracing::warn!("Failed to serialize outbound server message; dropping client send");
            break;
        };
        if !matches!(
            tokio::time::timeout(send_timeout, sink.send(Message::Text(json))).await,
            Ok(Ok(()))
        ) {
            break;
        }
    }
    shutdown.send_replace(true);
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

/// Complete the close handshake before dropping TCP, so a client polling less
/// often than the server can still read its admission error. Bound silent peers.
async fn reject_connection(
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
}

impl ClientSession {
    pub fn new(id: Uuid, tx: WsTx, gameplay_version: u32) -> Self {
        let (shutdown, _) = watch::channel(false);
        Self::with_shutdown(id, tx, gameplay_version, shutdown)
    }

    fn with_shutdown(
        id: Uuid,
        tx: WsTx,
        gameplay_version: u32,
        shutdown: watch::Sender<bool>,
    ) -> Self {
        Self {
            id,
            tx,
            gameplay_version,
            initialized: false,
            shutdown,
        }
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
}

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
        })
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

                    tokio::spawn(async move {
                        if serve_status_if_requested(&mut stream, &status).await {
                            return;
                        }
                        let permit = match admission.try_admit(addr.ip()) {
                            Ok(permit) => permit,
                            Err(code) => {
                                let _ = reject_before_hello(stream, code, handshake_timeout).await;
                                return;
                            }
                        };
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
    let body = match status.try_read() {
        Ok(live) => serde_json::to_string(&*live).unwrap_or_else(|_| "{}".into()),
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
    let message = if code == "address_limit" {
        "Too many connections from this address."
    } else {
        "This server is not taking more connections."
    };
    let _ = reject_connection(
        sink,
        stream,
        ServerMessage::Error {
            code: code.into(),
            message: message.into(),
        },
    )
    .await;
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
}

async fn handle_connection(
    stream: TcpStream,
    game_tx: mpsc::UnboundedSender<GameCommand>,
    clients: Arc<Mutex<Vec<ClientSession>>>,
    policy: HelloPolicy,
) -> Result<(), Box<dyn std::error::Error>> {
    let ws_stream = match tokio::time::timeout(
        policy.handshake_timeout,
        accept_async_with_config(stream, Some(websocket_limits())),
    )
    .await
    {
        Ok(Ok(stream)) => stream,
        Ok(Err(error)) => return Err(error.into()),
        Err(_) => return Ok(()),
    };
    let (mut ws_sink, mut ws_stream) = ws_stream.split();

    let (tx, rx): (WsTx, WsRx) = mpsc::channel(OUTBOUND_QUEUE_CAPACITY);
    let (shutdown_tx, mut shutdown_rx) = watch::channel(false);
    let client_id = Uuid::new_v4();

    let role;
    let player_id;
    // RAII returns seats after failed admission and development-party disconnect.
    // Solo admission consumes its permit for the server lifetime below.
    // A resume request parks the seat instead of returning it on a drop.
    let mut _party_seat;
    let mut keep_pawn = false;
    let mut left = false;

    let first = match tokio::time::timeout(policy.hello_timeout, ws_stream.next()).await {
        Ok(message) => message,
        Err(_) => return Ok(()),
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
                    return reject_connection(ws_sink, ws_stream, rejection).await;
                }
                if gameplay_version < policy.required_gameplay {
                    let rejection = ServerMessage::Error {
                        code: "unsupported_gameplay".into(),
                        message: format!(
                            "This server requires gameplay version {}; update your client.",
                            policy.required_gameplay
                        ),
                    };
                    return reject_connection(ws_sink, ws_stream, rejection).await;
                }
                if geometry_version < policy.required_geometry {
                    let rejection = ServerMessage::Error {
                        code: "unsupported_geometry".into(),
                        message: format!(
                            "This server requires geometry version {}; update your client.",
                            policy.required_geometry
                        ),
                    };
                    return reject_connection(ws_sink, ws_stream, rejection).await;
                }
                let mut resumed: Option<crate::resume::ResumeAccept> = None;
                if r != Role::Spectator {
                    if let Some(token) = resume.as_deref().filter(|token| !token.is_empty()) {
                        let Some((claimed_id, claimed_role, nonce)) = policy.resume.open(token)
                        else {
                            return reject_connection(
                                ws_sink,
                                ws_stream,
                                ServerMessage::Error {
                                    code: "resume_rejected".into(),
                                    message: "The previous pawn is gone.".into(),
                                },
                            )
                            .await;
                        };
                        if claimed_role != r {
                            return reject_connection(
                                ws_sink,
                                ws_stream,
                                ServerMessage::Error {
                                    code: "resume_rejected".into(),
                                    message: "The previous pawn is gone.".into(),
                                },
                            )
                            .await;
                        }
                        let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
                        clients.lock().await.push(ClientSession::with_shutdown(
                            client_id,
                            tx.clone(),
                            gameplay_version,
                            shutdown_tx.clone(),
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
                            return reject_connection(
                                ws_sink,
                                ws_stream,
                                ServerMessage::Error {
                                    code: "resume_rejected".into(),
                                    message: "The previous pawn is gone.".into(),
                                },
                            )
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
                    ws_sink
                        .send(Message::Text(serde_json::to_string(&welcome)?))
                        .await?;
                    tracing::info!("Client {:?} resumed {:?}", client_id, player_id);
                } else {
                    _party_seat = if r != Role::Spectator {
                        match policy.party_slots {
                            Some(slots) => match slots.try_acquire_owned() {
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
                                    return reject_connection(ws_sink, ws_stream, rejection).await;
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

                    ws_sink
                        .send(Message::Text(serde_json::to_string(&welcome)?))
                        .await?;

                    let mut clients_lock = clients.lock().await;
                    clients_lock.push(ClientSession::with_shutdown(
                        client_id,
                        tx.clone(),
                        gameplay_version,
                        shutdown_tx.clone(),
                    ));
                    drop(clients_lock);

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
                        "Client {:?} connected as {:?} (player_id: {:?})",
                        client_id,
                        r,
                        player_id
                    );
                }
            }
            _ => {
                tracing::warn!("Invalid hello message");
                return Ok(());
            }
        }
    } else {
        return Ok(());
    }

    let role = role.unwrap();

    let mut inbound = InboundBudget::new();
    let send_task = tokio::spawn(run_outbound_writer(
        ws_sink,
        rx,
        shutdown_tx,
        OUTBOUND_SEND_TIMEOUT,
    ));

    loop {
        let msg = tokio::select! {
            msg = ws_stream.next() => msg,
            changed = shutdown_rx.changed() => {
                if changed.is_err() || *shutdown_rx.borrow_and_update() {
                    break;
                }
                continue;
            }
        };
        let Some(msg) = msg else {
            break;
        };
        match msg {
            Ok(Message::Text(text)) => {
                if !inbound.allow() {
                    continue;
                }
                if matches!(
                    serde_json::from_str::<ClientMessage>(&text),
                    Ok(ClientMessage::Leave)
                ) {
                    left = true;
                    continue;
                }
                if role != Role::Spectator {
                    match serde_json::from_str::<ClientMessage>(&text) {
                        Ok(ClientMessage::Action(action)) => {
                            if let Some(pid) = player_id {
                                let _ = game_tx.send(GameCommand::Action {
                                    player_id: pid,
                                    action,
                                });
                            }
                        }
                        Ok(ClientMessage::MissionReady(ready)) => {
                            if let Some(player_id) = player_id {
                                let _ =
                                    game_tx.send(GameCommand::MissionReady { player_id, ready });
                            }
                        }
                        Ok(ClientMessage::MissionContinue(request)) => {
                            if let Some(player_id) = player_id {
                                let _ = game_tx
                                    .send(GameCommand::MissionContinue { player_id, request });
                            }
                        }
                        Ok(ClientMessage::Speak(speak)) => {
                            if let Some(pid) = player_id {
                                let _ = game_tx.send(GameCommand::Speak {
                                    player_id: pid,
                                    text: speak.text,
                                });
                            }
                        }
                        Ok(ClientMessage::SetDisplayBehavior(msg)) if role == Role::Agent => {
                            // Further gated in sim (rule bots / humans ignored).
                            if let Some(pid) = player_id {
                                let _ = game_tx.send(GameCommand::SetDisplayBehavior {
                                    player_id: pid,
                                    behavior: msg.behavior,
                                });
                            }
                        }
                        _ => {}
                    }
                }
            }
            Ok(Message::Close(_)) | Err(_) => break,
            _ => {}
        }
    }

    send_task.abort();

    if let Some(pid) = player_id {
        if keep_pawn && !left {
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

    tracing::info!("Client {:?} disconnected", client_id);

    Ok(())
}
