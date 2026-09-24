//! The authoritative tick loop, shared by the `fragr-server` binary and by
//! in-process harnesses such as the playtest tool. Binding on port 0 and the
//! `ready` channel let a caller learn the real address; `shutdown` ends the loop.

use crate::mission::run_file::store::RunStore;
use crate::mission::run_file::RunDocument;
use crate::net::NetServer;
use crate::protocol::CampaignDifficulty;
use crate::session::{broadcast_to_clients, send_unicasts, DeliveryStats, GameSession};
use crate::sim::{MapKind, MatchConfig};
use std::future::Future;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;
use tokio::sync::mpsc;

/// Optional in-process measurements for a local delivery test. The production
/// tick does not lock or retain these histograms unless a harness requests it.
#[derive(Debug, Default)]
pub struct RunMetrics {
    session_ns: crate::bench::Histogram,
    fanout_ns: crate::bench::Histogram,
    pub queued_messages: u64,
    pub queue_high_water: usize,
    pub queue_overflows: u64,
}

#[derive(Debug, serde::Serialize)]
pub struct RunMetricsReport {
    pub session_ms: crate::bench::Summary,
    pub fanout_enqueue_ms: crate::bench::Summary,
    pub queued_messages: u64,
    pub queue_high_water: usize,
    pub queue_overflows: u64,
}

impl RunMetrics {
    pub fn report(&self) -> RunMetricsReport {
        RunMetricsReport {
            session_ms: self.session_ns.summary(1e-6),
            fanout_enqueue_ms: self.fanout_ns.summary(1e-6),
            queued_messages: self.queued_messages,
            queue_high_water: self.queue_high_water,
            queue_overflows: self.queue_overflows,
        }
    }

    fn record_delivery(&mut self, delivery: DeliveryStats) {
        self.queued_messages += delivery.queued_messages;
        self.queue_high_water = self.queue_high_water.max(delivery.queue_high_water);
        self.queue_overflows += delivery.queue_overflows;
    }
}

/// Fixed simulation step: 20 Hz.
pub const TICK: Duration = Duration::from_millis(50);

pub(crate) struct LocalRunConfig {
    pub directory: PathBuf,
    pub resume: bool,
    pub difficulty_ready: tokio::sync::oneshot::Sender<CampaignDifficulty>,
}

/// Everything the loop needs besides the shutdown signal.
#[derive(Debug, Clone)]
pub struct ServerOptions {
    pub bind: String,
    pub bots: usize,
    pub map: MapKind,
    /// Authored file or bundled mission, mutually exclusive with arcade rules.
    pub authored: Option<crate::maps::AuthoredSource>,
    /// An explicit difficulty is valid only for a mission, never arcade or bench.
    pub difficulty: Option<crate::protocol::CampaignDifficulty>,
    pub campaign_run: bool,
    pub map_rotate: bool,
    /// Match rules override (frag limit, timers). `None` keeps the defaults.
    pub match_config: Option<MatchConfig>,
    /// Seed for the simulation's random stream, so a session can be reproduced.
    pub seed: u64,
    /// Seconds between status reports in the log; zero turns them off.
    pub status_every_s: u64,
    /// Set only by the dedicated or local process after reading the environment.
    /// Tests and the playtest harness leave this empty so hello stays open.
    pub join_secret: Option<std::sync::Arc<crate::join_ticket::JoinSecret>>,
    /// Host ban and allow list files. Empty leaves every address admissible.
    pub access: crate::access::AccessConfig,
    /// Contested Frequency Solo Broadcast Episode 0 (Calibration / Larak Lot).
    pub solo_broadcast: bool,
}

impl Default for ServerOptions {
    fn default() -> Self {
        ServerOptions {
            bind: "0.0.0.0:6767".to_string(),
            bots: 4,
            map: MapKind::default(),
            authored: None,
            difficulty: None,
            campaign_run: false,
            map_rotate: false,
            match_config: None,
            solo_broadcast: false,
            seed: 1,
            status_every_s: 60,
            join_secret: None,
            access: crate::access::AccessConfig::default(),
        }
    }
}

/// Bind, accept clients, and tick the session until `shutdown` resolves.
/// When `ready` is Some, send the bound address once accept is live.
pub async fn run_server(
    options: ServerOptions,
    shutdown: impl Future<Output = ()>,
    ready: Option<tokio::sync::oneshot::Sender<SocketAddr>>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    run_server_impl(options, shutdown, ready, None, None).await
}

pub(crate) async fn run_local_server(
    options: ServerOptions,
    shutdown: impl Future<Output = ()>,
    ready: tokio::sync::oneshot::Sender<SocketAddr>,
    local_run: LocalRunConfig,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    run_server_impl(options, shutdown, Some(ready), None, Some(local_run)).await
}

pub async fn run_server_with_metrics(
    options: ServerOptions,
    shutdown: impl Future<Output = ()>,
    ready: Option<tokio::sync::oneshot::Sender<SocketAddr>>,
    metrics: std::sync::Arc<std::sync::Mutex<RunMetrics>>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    run_server_impl(options, shutdown, ready, Some(metrics), None).await
}

async fn run_server_impl(
    options: ServerOptions,
    shutdown: impl Future<Output = ()>,
    ready: Option<tokio::sync::oneshot::Sender<SocketAddr>>,
    metrics: Option<std::sync::Arc<std::sync::Mutex<RunMetrics>>>,
    local_run: Option<LocalRunConfig>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Complete bounded topology construction before advertising readiness.
    // Keep it off the async executor, including single-threaded local harnesses.
    let map = options.map;
    let rotate = options.map_rotate;
    if (options.difficulty.is_some() || options.campaign_run) && options.authored.is_none() {
        return Err("difficulty requires an authored mission".into());
    }
    if options.authored.is_some()
        && (rotate
            || options.solo_broadcast
            || options.bots > 0
            || options.match_config.is_some()
            || map != MapKind::default())
    {
        return Err(
            "authored traversal requires --bots 0 and no arcade map, rotation or rule overrides"
                .into(),
        );
    }
    // A list that does not parse refuses to start rather than opening the door.
    let access = if options.access.is_empty() {
        None
    } else {
        Some(crate::access::AccessControl::load(options.access.clone())?)
    };
    let authored = options.authored.clone();
    let mut session = tokio::task::spawn_blocking(move || -> std::io::Result<GameSession> {
        match authored {
            Some(source) => Ok(GameSession::with_authored_map(source.load()?)),
            None => Ok(GameSession::with_map(map, rotate)),
        }
    })
    .await??;
    let mut run_store: Option<RunStore> = None;
    let mut last_run_document: Option<RunDocument> = None;
    if let Some(local_run) = local_run {
        if !options.campaign_run
            || !matches!(
                options.authored,
                Some(crate::maps::AuthoredSource::Mission(_))
            )
        {
            return Err("durable local run requires a bundled campaign mission".into());
        }
        let content_sha256 = session
            .state
            .map
            .content_sha256()
            .ok_or("durable local run requires authored content")?;
        let store = RunStore::open(&local_run.directory, content_sha256)?;
        if local_run.resume {
            let saved = store.load()?.ok_or("no saved campaign run to resume")?;
            session.state.load_campaign_run(&saved)?;
            last_run_document = Some(saved);
        } else {
            session
                .state
                .set_campaign_difficulty(options.difficulty.unwrap_or_default())?;
            session.state.enable_campaign_run()?;
            let mission = session
                .state
                .mission_state()
                .ok_or("campaign mission is missing")?;
            let initial = RunDocument::new(
                mission.run.ok_or("campaign run is missing")?.id,
                mission.rules,
                content_sha256,
            );
            store.start_new(&initial)?;
            last_run_document = Some(initial);
        }
        let _ = local_run
            .difficulty_ready
            .send(session.state.campaign_rules().difficulty);
        run_store = Some(store);
    } else {
        if let Some(difficulty) = options.difficulty {
            session.state.set_campaign_difficulty(difficulty)?;
        }
        if options.campaign_run {
            session.state.enable_campaign_run()?;
        }
    }
    if session.state.map.mission().is_some() {
        tracing::info!(rules = ?session.state.campaign_rules(), "Campaign rules selected");
    }
    let (game_tx, mut game_rx) = mpsc::unbounded_channel();

    // Rotation advertises the maximum requirement before a client joins, so
    // switching maps cannot strand a legacy client inside a misrendered slab.
    let required_geometry = if options.authored.is_some() {
        crate::protocol::geometry_version(&session.state.map.arena().solids)
    } else {
        MapKind::ALL
            .into_iter()
            .filter(|candidate| rotate || *candidate == map)
            .map(|candidate| {
                crate::protocol::geometry_version(&crate::maps::arena(candidate).solids)
            })
            .max()
            .unwrap_or_else(crate::protocol::legacy_geometry_version)
    };
    // Discovery equipment delivers the private loadout, whose shape changed in
    // the ammunition contract. Full-arsenal arcade maps keep older readers.
    let discovery =
        session.state.map.equipment_policy() == crate::protocol::EquipmentPolicy::Discovery;
    let required_gameplay = if discovery {
        crate::protocol::AMMO_GAMEPLAY_VERSION
    } else if session.state.map.m02_objectives().is_some() {
        crate::protocol::M02_GAMEPLAY_VERSION
    } else if options.campaign_run {
        crate::protocol::CONTINUES_GAMEPLAY_VERSION
    } else if session.state.map.mission().is_some() {
        crate::protocol::DIFFICULTY_GAMEPLAY_VERSION
    } else if session.state.map.has_encounters() {
        crate::protocol::CAMPAIGN_GAMEPLAY_VERSION
    } else {
        match session.state.map.equipment_policy() {
            crate::protocol::EquipmentPolicy::FullArsenal => 1,
            crate::protocol::EquipmentPolicy::Discovery => {
                crate::protocol::DISCOVERY_GAMEPLAY_VERSION
            }
        }
    };
    let live = std::sync::Arc::new(tokio::sync::RwLock::new(session.state.live_status(0)));
    let mut net_server = NetServer::bind_with_requirements(
        &options.bind,
        game_tx.clone(),
        required_geometry,
        required_gameplay,
    )
    .await?;
    net_server.share_status(std::sync::Arc::clone(&live));
    net_server.share_resume(std::sync::Arc::clone(&session.resume));
    session.resume.note_tick(session.state.tick);
    if let Some(secret) = options.join_secret.clone() {
        net_server.set_join_secret(secret);
    }
    if options.campaign_run {
        net_server.reserve_solo_run()?;
    }
    let access_reload = access.map(|control| {
        let (bans, allows) = control.summary();
        tracing::info!(
            target: crate::net::AUDIT_TARGET,
            event = "lists_loaded",
            bans = ?bans,
            allows = ?allows,
        );
        net_server.set_access(control.subscribe());
        AbortOnDrop(tokio::spawn(control.watch(crate::access::RELOAD_EVERY)))
    });
    if let Some(tx) = ready {
        let _ = tx.send(net_server.local_addr()?);
    }
    let clients = net_server.clients.clone();

    tokio::spawn(async move {
        net_server.accept_loop().await;
    });

    session.state.seed(options.seed);
    if let Some(config) = options.match_config {
        session.state.config = config;
    }
    session.spawn_bots(options.bots);
    if options.solo_broadcast {
        session.enable_solo_broadcast_ep0();
        tracing::info!("Solo Broadcast Episode 0 armed (Calibration / Larak Lot)");
    }
    tracing::info!(
        "Map: {} (id {}){}",
        session.state.map.name(),
        session.state.map.id(),
        if options.map_rotate {
            ", rotate each round"
        } else {
            ""
        }
    );

    let mut tick_interval = tokio::time::interval(TICK);
    tick_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut stats = crate::bench::TickStats::new();
    let mut status_interval = (options.status_every_s > 0).then(|| {
        let mut i = tokio::time::interval(Duration::from_secs(options.status_every_s));
        i.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        i
    });
    tracing::info!("Simulation seed: {}", options.seed);

    tracing::info!("Game loop starting (20 Hz tick)");

    tokio::pin!(shutdown);

    loop {
        tokio::select! {
            _ = tick_interval.tick() => {
                let started = std::time::Instant::now();
                let expired = session.resume.expire(session.state.tick);
                for player_id in expired {
                    session.drop_expired_pawn(player_id);
                }
                let messages = session.tick_messages(TICK.as_secs_f32());
                persist_local_run(&session.state, run_store.as_ref(), &mut last_run_document)?;
                session.resume.note_tick(session.state.tick);
                let elapsed = started.elapsed();
                let bytes = crate::bench::encoded_payload_bytes(messages.iter())?;
                stats.record_tick(elapsed, bytes);
                let fanout_started = std::time::Instant::now();
                let delivery = broadcast_to_clients(&clients, &messages).await;
                let broadcast_elapsed = fanout_started.elapsed();
                {
                    let connections = clients.lock().await.len();
                    if let Ok(mut slot) = live.try_write() {
                        *slot = session.state.live_status(connections);
                    }
                }
                let unicasts = session.take_unicasts();
                let unicast_started = std::time::Instant::now();
                let unicast_delivery = send_unicasts(&clients, &session.client_to_player, &unicasts).await;
                let fanout_elapsed = broadcast_elapsed.saturating_add(unicast_started.elapsed());
                if let Some(metrics) = &metrics {
                    let mut metrics = metrics.lock().unwrap_or_else(|poison| poison.into_inner());
                    metrics.session_ns.record(elapsed.as_nanos().min(u64::MAX as u128) as u64);
                    metrics.fanout_ns.record(fanout_elapsed.as_nanos().min(u64::MAX as u128) as u64);
                    metrics.record_delivery(delivery);
                    metrics.record_delivery(unicast_delivery);
                }
            }

            _ = async { status_interval.as_mut().expect("guarded").tick().await },
                if status_interval.is_some() && stats.ticks() > 0 =>
            {
                let fighters = session.state.players.len();
                let client_count = clients.lock().await.len();
                let report = stats.report(fighters, client_count);
                match serde_json::to_string(&report) {
                    Ok(json) => tracing::info!("STATUS {json}"),
                    Err(err) => tracing::warn!("status report could not be encoded: {err}"),
                }
            }

            Some(cmd) = game_rx.recv() => {
                session.apply_command(cmd);
                persist_local_run(&session.state, run_store.as_ref(), &mut last_run_document)?;
                let unicasts = session.take_unicasts();
                let delivery = send_unicasts(&clients, &session.client_to_player, &unicasts).await;
                if let Some(metrics) = &metrics {
                    metrics.lock().unwrap_or_else(|poison| poison.into_inner()).record_delivery(delivery);
                }
            }

            _ = &mut shutdown => {
                tracing::info!("Server shutdown requested");
                break;
            }
        }
    }
    drop(access_reload);

    Ok(())
}

/// Ends the list reloader with the loop, including on an early error return.
struct AbortOnDrop(tokio::task::JoinHandle<()>);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

fn persist_local_run(
    state: &crate::sim::GameState,
    store: Option<&RunStore>,
    previous: &mut Option<RunDocument>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let Some(store) = store else { return Ok(()) };
    let Some(document) = state.campaign_run_document()? else {
        return Ok(());
    };
    if previous.as_ref() != Some(&document) {
        store.save(&document)?;
        *previous = Some(document);
    }
    Ok(())
}
