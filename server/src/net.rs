use crate::protocol::{ClientMessage, Role, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, Mutex, Semaphore};
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::{accept_async_with_config, tungstenite::Message};
use uuid::Uuid;

type ServerSocket = tokio_tungstenite::WebSocketStream<TcpStream>;

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
const MAX_CONNECTIONS_PER_IP: usize = 16;
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

pub type WsTx = mpsc::UnboundedSender<ServerMessage>;
pub type WsRx = mpsc::UnboundedReceiver<ServerMessage>;

pub struct ClientSession {
    pub id: Uuid,
    pub tx: WsTx,
    pub(crate) gameplay_version: u32,
    /// Broadcasts must follow the initial targeted geometry in this queue.
    pub(crate) initialized: bool,
}

impl ClientSession {
    pub fn new(id: Uuid, tx: WsTx, gameplay_version: u32) -> Self {
        Self {
            id,
            tx,
            gameplay_version,
            initialized: false,
        }
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
        })
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
                Ok((stream, addr)) => {
                    tracing::debug!("New connection from {}", addr);
                    let game_tx = self.game_tx.clone();
                    let clients = self.clients.clone();
                    let geometry_version = self.geometry_version;
                    let gameplay_version = self.gameplay_version;
                    let party_slots = self.party_slots.clone();
                    let solo_run = self.solo_run;
                    let admission = Arc::clone(&self.admission);
                    let handshake_timeout = admission.handshake_timeout;
                    let hello_timeout = admission.hello_timeout;

                    tokio::spawn(async move {
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

    let (tx, mut rx): (WsTx, WsRx) = mpsc::unbounded_channel();
    let client_id = Uuid::new_v4();

    let role;
    let player_id;
    // RAII returns seats after failed admission and development-party disconnect.
    // Solo admission consumes its permit for the server lifetime below.
    let mut _party_seat;

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
            }) => {
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

                let welcome = ServerMessage::Welcome {
                    player_id,
                    role: r,
                    mode_name: crate::protocol::default_mode_name(),
                    playlist: crate::protocol::default_playlist(),
                };

                ws_sink
                    .send(Message::Text(serde_json::to_string(&welcome)?))
                    .await?;

                let mut clients_lock = clients.lock().await;
                clients_lock.push(ClientSession::new(client_id, tx.clone(), gameplay_version));
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
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            let Ok(json) = serde_json::to_string(&msg) else {
                tracing::warn!("Failed to serialize outbound server message; dropping client send");
                break;
            };
            if ws_sink.send(Message::Text(json)).await.is_err() {
                break;
            }
        }
    });

    while let Some(msg) = ws_stream.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                if !inbound.allow() {
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

    game_tx.send(GameCommand::Disconnected { id: client_id })?;

    let mut clients_lock = clients.lock().await;
    clients_lock.retain(|c| c.id != client_id);

    tracing::info!("Client {:?} disconnected", client_id);

    Ok(())
}
