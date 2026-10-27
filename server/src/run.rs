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
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::sync::mpsc;

/// Optional in-process measurements for a local delivery test. The production
/// tick does not lock or retain these histograms unless a harness requests it.
#[derive(Debug, Default)]
pub struct RunMetrics {
    session_ns: crate::bench::Histogram,
    broadcast_encode_ns: crate::bench::Histogram,
    fanout_ns: crate::bench::Histogram,
    /// The whole tick handler, start to the end of delivery queuing.
    tick_ns: crate::bench::Histogram,
    /// How long after its scheduled deadline each tick handler began.
    late_ns: crate::bench::Histogram,
    /// Whole periods the interval skipped because the loop fell behind.
    pub skipped_periods: u64,
    /// Handlers at or above the 50 ms budget.
    pub over_budget: u64,
    previous_deadline: Option<std::time::Instant>,
    pub queued_messages: u64,
    pub queue_high_water: usize,
    pub queue_overflows: u64,
    pub replaced_worlds: u64,
    writer: std::sync::Arc<crate::net::WriterProbe>,
    tick_starts: std::collections::VecDeque<(u64, std::time::Instant)>,
}

/// Enough tick starts for a two minute row at 20 Hz, twice over.
const TICK_STARTS_KEPT: usize = 4800;

#[derive(Debug, serde::Serialize)]
pub struct RunMetricsReport {
    pub session_ms: crate::bench::Summary,
    /// Encoding every broadcast once on the tick task, which also counts its bytes.
    pub broadcast_encode_ms: crate::bench::Summary,
    pub fanout_enqueue_ms: crate::bench::Summary,
    /// The whole tick handler: session, encode, enqueue and status refresh.
    pub tick_ms: crate::bench::Summary,
    /// Handler start after its scheduled deadline.
    pub late_ms: crate::bench::Summary,
    pub skipped_periods: u64,
    pub over_budget: u64,
    pub queued_messages: u64,
    pub queue_high_water: usize,
    pub queue_overflows: u64,
    pub replaced_worlds: u64,
    pub writer: crate::net::WriterReport,
}

impl RunMetrics {
    pub fn report(&self) -> RunMetricsReport {
        RunMetricsReport {
            session_ms: self.session_ns.summary(1e-6),
            broadcast_encode_ms: self.broadcast_encode_ns.summary(1e-6),
            fanout_enqueue_ms: self.fanout_ns.summary(1e-6),
            tick_ms: self.tick_ns.summary(1e-6),
            late_ms: self.late_ns.summary(1e-6),
            skipped_periods: self.skipped_periods,
            over_budget: self.over_budget,
            queued_messages: self.queued_messages,
            queue_high_water: self.queue_high_water,
            queue_overflows: self.queue_overflows,
            replaced_worlds: self.replaced_worlds,
            writer: self.writer.report(),
        }
    }

    /// Start a measured window. Live writers keep reporting into the same probe.
    pub fn reset(&mut self) {
        self.session_ns.clear();
        self.broadcast_encode_ns.clear();
        self.fanout_ns.clear();
        self.tick_ns.clear();
        self.late_ns.clear();
        self.skipped_periods = 0;
        self.over_budget = 0;
        self.queued_messages = 0;
        self.queue_high_water = 0;
        self.queue_overflows = 0;
        self.replaced_worlds = 0;
        self.writer.reset();
        self.tick_starts.clear();
    }

    /// When each recent tick started, keyed by the Snapshot tick it built.
    pub fn tick_starts(&self) -> impl Iterator<Item = (u64, std::time::Instant)> + '_ {
        self.tick_starts.iter().copied()
    }

    fn record_tick_start(&mut self, tick: u64, started: std::time::Instant) {
        if self.tick_starts.len() == TICK_STARTS_KEPT {
            self.tick_starts.pop_front();
        }
        self.tick_starts.push_back((tick, started));
    }

    /// One served tick's deadline, lateness and whole handler duration.
    fn record_schedule(
        &mut self,
        deadline: std::time::Instant,
        started: std::time::Instant,
        total: Duration,
    ) {
        self.skipped_periods =
            self.skipped_periods
                .saturating_add(crate::tick_trace::skipped_periods(
                    self.previous_deadline,
                    deadline,
                    TICK,
                ));
        self.previous_deadline = Some(deadline);
        let nanos = |duration: Duration| u64::try_from(duration.as_nanos()).unwrap_or(u64::MAX);
        self.late_ns
            .record(nanos(started.saturating_duration_since(deadline)));
        self.tick_ns.record(nanos(total));
        self.over_budget += u64::from(total >= TICK);
    }

    fn record_delivery(&mut self, delivery: DeliveryStats) {
        self.queued_messages += delivery.queued_messages;
        self.queue_high_water = self.queue_high_water.max(delivery.queue_high_water);
        self.queue_overflows += delivery.queue_overflows;
        self.replaced_worlds += delivery.replaced_worlds;
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
    pub bot_policy: crate::bot_fill::BotPolicy,
    pub fill_target: usize,
    pub map: MapKind,
    /// Authored file or bundled mission, mutually exclusive with arcade rules.
    pub authored: Option<crate::maps::AuthoredSource>,
    /// An explicit difficulty is valid only for a mission, never arcade or bench.
    pub difficulty: Option<crate::protocol::CampaignDifficulty>,
    pub campaign_run: bool,
    pub map_rotate: bool,
    /// Built-in night list. The process stays up and changes map and mode.
    pub playlist: bool,
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
    /// Scrap League Solo Broadcast Episode 0 (Calibration / Larak Lot).
    pub solo_broadcast: bool,
    /// Opt-in local venue desk. Closing its input does not stop the match.
    pub console: bool,
    /// Exact ticket audience. Empty keeps replayable local v1 tickets.
    pub join_audience: Option<String>,
    /// Exact browser Origin values. Empty rejects every present Origin.
    pub origin_allow: Vec<String>,
    /// Spectators present a ticket only when a join secret is also set.
    pub spectator_tickets: bool,
    /// Dedicated server summary line for humans after preflight checks complete.
    pub human_summary: bool,
    /// Operator overview on stdout (ready card and pulse lines) in place of
    /// the STATUS JSON log line. `None` keeps the plain log stream.
    pub overview: Option<crate::operator::Style>,
    /// Opt-in per-tick timing file for stutter diagnosis (`tick_trace.rs`).
    pub tick_trace: Option<PathBuf>,
    /// The head-to-head book on disk (`statistics::HeadToHead`): loaded at
    /// start and saved when a round ends and at shutdown. A desktop host
    /// keeps it beside its runs; a dedicated server only when asked.
    pub head_to_head: Option<PathBuf>,
}

impl Default for ServerOptions {
    fn default() -> Self {
        ServerOptions {
            bind: "0.0.0.0:6767".to_string(),
            bots: 4,
            bot_policy: crate::bot_fill::BotPolicy::Fixed,
            fill_target: 0,
            map: MapKind::default(),
            authored: None,
            difficulty: None,
            campaign_run: false,
            map_rotate: false,
            playlist: false,
            match_config: None,
            solo_broadcast: false,
            seed: 1,
            status_every_s: 60,
            join_secret: None,
            access: crate::access::AccessConfig::default(),
            console: false,
            join_audience: None,
            origin_allow: Vec::new(),
            spectator_tickets: false,
            human_summary: false,
            overview: None,
            tick_trace: None,
            head_to_head: None,
        }
    }
}

/// Bind, accept clients, and tick the session until `shutdown` resolves.
/// When `ready` is Some, send the bound address only after loopback
/// `GET /status` has returned a schema 2 match line.
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
    options.validate_bot_policy()?;
    // Keep it off the async executor, including single-threaded local harnesses.
    let map = options.map;
    let rotate = options.map_rotate;
    let playlist = options.playlist;
    if playlist
        && (rotate
            || options.authored.is_some()
            || options.solo_broadcast
            || options.match_config.is_some()
            || options.campaign_run
            || options.difficulty.is_some())
    {
        return Err(
            "the night playlist owns the map and the mode for the life of the process".into(),
        );
    }
    if playlist {
        crate::sim::GameState::validate_night_playlist().map_err(std::io::Error::other)?;
    }
    if let Some(config) = options
        .match_config
        .as_ref()
        .filter(|config| config.sabotage.five_vs_five)
    {
        if config.rules.mode() != crate::protocol::GameMode::Sabotage || options.bots > 10 {
            return Err(
                "five versus five requires Sabotage and at most ten initial rule bots".into(),
            );
        }
        if config.rules.only_weapon().is_some() {
            return Err(
                "five versus five Sabotage requires the finite Pistol start, without weapon-only mutators"
                    .into(),
            );
        }
    }
    if options.match_config.as_ref().is_some_and(|config| {
        config.rules.mode() == crate::protocol::GameMode::Duel
            && (options.bots > 2 || config.sabotage.five_vs_five)
    }) {
        return Err("a duel has two fighter seats: at most two initial rule bots".into());
    }
    if options
        .match_config
        .as_ref()
        .is_some_and(|config| config.rules.mode() == crate::protocol::GameMode::Ctf)
        && (rotate || options.authored.is_some() || map.ctf_stands().is_none())
    {
        return Err(
            "capture the flag requires a map with validated flag stands and no rotation".into(),
        );
    }
    if options
        .match_config
        .as_ref()
        .is_some_and(|config| config.rules.mode() == crate::protocol::GameMode::Sabotage)
        && (rotate || options.authored.is_some() || map.sabotage_map().is_none())
    {
        return Err(
            "sabotage requires a map with validated sites (Sector 9 or Low Water) and no rotation"
                .into(),
        );
    }
    if options
        .match_config
        .as_ref()
        .is_some_and(|config| config.rules.mode() == crate::protocol::GameMode::Conquest)
        && (rotate || options.authored.is_some() || map != crate::sim::MapKind::HoldfastAtoll)
    {
        return Err("conquest requires Holdfast Atoll and no rotation".into());
    }
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
            None if playlist => Ok(GameSession::with_playlist()),
            None => Ok(GameSession::with_map(map, rotate)),
        }
    })
    .await??;
    let mut durable_run: Option<DurableRun> = None;
    let epilogue =
        session.state.map.campaign_mission_id() == Some(crate::protocol::MissionId::StillHere);
    if epilogue {
        // Still Here keeps no save and runs no solo run. A saved survival
        // opens it, read without the writer lock, and nothing writes it back.
        if options.campaign_run {
            return Err("Still Here runs no campaign run of its own".into());
        }
        if let Some(local_run) = local_run {
            if !local_run.resume {
                return Err("Still Here opens read-only from a saved survival".into());
            }
            let hashes = crate::mission::run_file::store::CAMPAIGN_MISSIONS
                .map(crate::maps::AuthoredSource::bundled_content_sha256);
            let saved = match RunStore::inspect_with_hashes(&local_run.directory, hashes)? {
                crate::mission::run_file::store::RunProbe::Compatible(document) => *document,
                _ => return Err("no saved campaign survival to open Still Here".into()),
            };
            session.state.load_epilogue_entitlement(
                &saved,
                hashes[crate::mission::run_file::store::stage_index(
                    crate::protocol::MissionId::LocalException,
                )],
            )?;
            let _ = local_run
                .difficulty_ready
                .send(session.state.campaign_rules().difficulty);
        } else if let Some(difficulty) = options.difficulty {
            session.state.set_campaign_difficulty(difficulty)?;
        }
    } else if let Some(local_run) = local_run {
        if !options.campaign_run
            || !matches!(
                options.authored,
                Some(crate::maps::AuthoredSource::Mission(_))
            )
        {
            return Err("durable local run requires a bundled campaign mission".into());
        }
        let run = DurableRun::open(
            &mut session,
            &local_run.directory,
            local_run.resume,
            options.difficulty,
        )?;
        let _ = local_run
            .difficulty_ready
            .send(session.state.campaign_rules().difficulty);
        durable_run = Some(run);
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
    let (game_tx, mut game_rx) = crate::net::game_channel();

    // Rotation advertises the maximum requirement before a client joins, so
    // switching maps cannot strand a legacy client inside a misrendered slab.
    let required_geometry = if options.authored.is_some() {
        crate::protocol::geometry_version(&session.state.map.arena().solids)
    } else {
        MapKind::ALL
            .into_iter()
            .filter(|candidate| rotate || playlist || *candidate == map)
            .map(|candidate| {
                crate::protocol::geometry_version(&crate::maps::arena(candidate).solids)
            })
            .max()
            .unwrap_or_else(crate::protocol::legacy_geometry_version)
    };
    // Discovery equipment delivers the private loadout, whose weapons now
    // include the Shiv. Full-arsenal arcade maps keep older readers.
    let discovery =
        session.state.map.equipment_policy() == crate::protocol::EquipmentPolicy::Discovery;
    // Sides, lives and the golden Railgun need a client that renders them.
    let twisted = options
        .match_config
        .as_ref()
        .is_some_and(|config| !config.rules.is_plain());
    let has_jammer = session.state.map.encounters().iter().any(|encounter| {
        encounter
            .enemies
            .iter()
            .any(|enemy| enemy.kind == crate::protocol::EnemyKind::Jammer)
    });
    let has_notary = session.state.map.encounters().iter().any(|encounter| {
        encounter
            .enemies
            .iter()
            .any(|enemy| enemy.kind == crate::protocol::EnemyKind::Notary)
    });
    let required_gameplay = if let Some(mission) = session.state.map.campaign_mission_id() {
        mission.gameplay_version()
    } else if session.state.map.requires_surveyor_contract() {
        crate::protocol::M20_GAMEPLAY_VERSION
    } else if session.state.map.requires_article_blade_contract() {
        crate::protocol::BLADE_GAMEPLAY_VERSION
    } else if session.state.map.m14_geometry().is_some() {
        crate::protocol::M14_GAMEPLAY_VERSION
    } else if session.state.map.walker_geometry().is_some() {
        crate::protocol::WALKER_GAMEPLAY_VERSION
    } else if map == MapKind::LowWater || rotate {
        crate::protocol::LOW_WATER_SABOTAGE_GAMEPLAY_VERSION
    } else if session.state.map.m13_geometry().is_some() {
        crate::protocol::M13_GAMEPLAY_VERSION
    } else if session.state.map.m12_geometry().is_some() {
        crate::protocol::M12_GAMEPLAY_VERSION
    } else if session.state.map.is_campaign() || session.state.map.requires_assessor_contract() {
        crate::protocol::ASSESSOR_GAMEPLAY_VERSION
    } else if session.state.map.requires_arc_contract() {
        crate::protocol::ARC_GAMEPLAY_VERSION
    } else if session.state.map.has_authored_vehicles() {
        crate::protocol::VEHICLE_GAMEPLAY_VERSION
    } else if session.state.map.requires_m11_contract() {
        crate::protocol::M11_GAMEPLAY_VERSION
    } else if session.state.map.requires_m10_contract() {
        crate::protocol::M10_GAMEPLAY_VERSION
    } else if session.state.map.requires_repeater_contract() {
        crate::protocol::REPEATER_GAMEPLAY_VERSION
    } else if session.state.map.requires_enforcer_contract() {
        crate::protocol::M09_GAMEPLAY_VERSION
    } else if session.state.map.campaign_mission_id()
        == Some(crate::protocol::MissionId::CustodianOfRecord)
    {
        crate::protocol::M08_GAMEPLAY_VERSION
    } else if session.state.map.campaign_mission_id()
        == Some(crate::protocol::MissionId::DeclaredGoods)
    {
        crate::protocol::M07_GAMEPLAY_VERSION
    } else if session.state.map.requires_sniper_contract() {
        crate::protocol::SNIPER_GAMEPLAY_VERSION
    } else if session.state.map.has_custody_devices() {
        crate::protocol::CUSTODY_GAMEPLAY_VERSION
    } else if session.state.map.campaign_mission_id()
        == Some(crate::protocol::MissionId::PortOfEntry)
    {
        crate::protocol::M06_GAMEPLAY_VERSION
    } else if discovery || has_notary || session.state.map.campaign_mission_id().is_some() {
        crate::protocol::M05_GAMEPLAY_VERSION
    } else if has_jammer {
        crate::protocol::JAMMER_GAMEPLAY_VERSION
    } else if playlist {
        // Replaced for a shared room below. The Sabotage floor alone would
        // still let an older client into the opening free-for-all.
        crate::protocol::SABOTAGE_GAMEPLAY_VERSION
    } else if options
        .match_config
        .as_ref()
        .is_some_and(|config| config.rules.mode() == crate::protocol::GameMode::Sabotage)
    {
        crate::protocol::SABOTAGE_GAMEPLAY_VERSION
    } else if options
        .match_config
        .as_ref()
        .is_some_and(|config| config.rules.mode() == crate::protocol::GameMode::Ctf)
    {
        crate::protocol::CTF_GAMEPLAY_VERSION
    } else if discovery || twisted {
        crate::protocol::RULES_GAMEPLAY_VERSION
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
    // One contract in a shared room. Campaign missions keep the floor above.
    // Every hello still refuses a version this binary does not implement.
    let shared_room = !options.campaign_run && !session.state.map.is_campaign();
    let required_gameplay = if shared_room {
        crate::protocol::GAMEPLAY_VERSION
    } else {
        required_gameplay
    };
    let required_geometry = if shared_room {
        crate::protocol::GEOMETRY_VERSION
    } else {
        required_geometry
    };
    session.state.seed(options.seed);
    if let Some(config) = options.match_config {
        session.state.apply_config(config);
    }
    // Opened before the listener so a bad path fails the start, not the match.
    let mut tick_trace = match options.tick_trace.as_deref() {
        Some(path) => {
            let trace =
                crate::tick_trace::TickTrace::create(path, TICK, crate::metrics::build_info())
                    .map_err(|error| -> Box<dyn std::error::Error + Send + Sync> {
                        format!("Tick trace {} could not be opened: {error}", path.display()).into()
                    })?;
            tracing::info!("Tick trace: writing {}", path.display());
            Some(trace)
        }
        None => None,
    };
    let live = std::sync::Arc::new(tokio::sync::RwLock::new(session.state.live_status(0)));
    let mut net_server = NetServer::bind_with_requirements(
        &options.bind,
        game_tx.clone(),
        required_geometry,
        required_gameplay,
    )
    .await?;
    if shared_room {
        net_server.require_client_aim();
    }
    // Capability 4 and above installs a four-seat mission party. A shared
    // room's contract is the current gameplay version, which is above that.
    // The arcade roster stays open. Sabotage replaces this with its own pool.
    if shared_room || (twisted && !discovery) || playlist {
        net_server.open_arena_seats();
    }
    if let Some(slots) = session.configure_fighter_seats() {
        net_server.set_fighter_seats(slots, session.state.config.rules.mode());
        net_server.set_seat_holds(session.seat_holds());
    }
    if options.bot_policy == crate::bot_fill::BotPolicy::Auto {
        session.set_auto_fill(options.fill_target);
        net_server.set_auto_fill();
    }
    net_server.share_status(std::sync::Arc::clone(&live));
    net_server.share_resume(std::sync::Arc::clone(&session.resume));
    if let Some(metrics) = &metrics {
        let metrics = metrics.lock().unwrap_or_else(|poison| poison.into_inner());
        net_server.set_writer_probe(std::sync::Arc::clone(&metrics.writer));
    }
    session.resume.note_tick(session.state.tick);
    if let Some(secret) = options.join_secret.clone() {
        net_server.set_join_secret(secret);
    }
    let population = crate::admission_bounds::Population::default();
    session.share_population(population.clone());
    net_server.share_population(population);
    net_server.set_admission_policy(
        options.join_audience.clone(),
        options.origin_allow.clone(),
        options.spectator_tickets,
    );
    if options.campaign_run {
        net_server.reserve_solo_run()?;
        net_server.set_solo_bound_body(session.state.campaign_run_body());
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
    let bound = net_server.local_addr()?;
    let clients = net_server.clients.clone();
    crate::metrics::mark_process_start();
    let mut tracker = crate::metrics::StatusTracker::new(net_server.traffic_totals(), TICK);

    // Accept must be running before the probe, and ready must wait until the
    // probe succeeds. A client that connects the moment ready fires can then
    // read the same match line.
    let mut accept_task = AbortOnDrop(tokio::spawn(async move {
        net_server.accept_loop().await;
    }));
    let probe_addr = crate::preflight::loopback_probe_addr(bound);
    let facts = crate::preflight::require_status(probe_addr).await.map_err(
        |error| -> Box<dyn std::error::Error + Send + Sync> {
            format!("Status preflight failed: {error}").into()
        },
    )?;
    tracing::info!(
        target: crate::logging::STARTUP_TARGET,
        "Status preflight: {probe_addr} answered. {map}, {kind}.",
        map = facts.map,
        kind = facts.kind
    );
    let joins = crate::preflight::join_checks(bound).await;
    let desk_wanted = options.console && options.authored.is_none() && !options.campaign_run;
    if options.human_summary {
        let addr = joins.primary(bound);
        let map_name = session.state.map.name();
        let mode_name = if session.state.map.is_authored() {
            "Campaign"
        } else {
            session.state.config.rules.mode().name()
        };
        println!("ready ws://{addr} {map_name} {mode_name} Ctrl-C stops");
    }
    if let Some(style) = options.overview {
        let facts = crate::operator::ReadyFacts {
            version: env!("FRAGR_CLI_VERSION").to_string(),
            map: session.state.map.name().to_string(),
            rules: if session.state.map.is_authored() {
                "Campaign".to_string()
            } else {
                session.state.config.rules.name()
            },
            campaign: options.authored.is_some() || options.campaign_run,
            playlist,
            map_rotate: rotate,
            bot_policy: options.bot_policy,
            bots: options.bots,
            fill_target: options.fill_target,
            joins: joins.clone(),
            ticketed: options.join_secret.is_some(),
            spectator_tickets: options.spectator_tickets && options.join_secret.is_some(),
            ban_list: options.access.ban_list.is_some(),
            allow_list: options.access.allow_list.is_some(),
            connection_cap: crate::net::connection_cap(),
            address_cap: crate::net::address_cap(),
            desk: match (options.console, desk_wanted) {
                (false, _) => crate::operator::DeskState::Off,
                (true, true) => crate::operator::DeskState::On,
                (true, false) => crate::operator::DeskState::Unavailable,
            },
            status_every_s: options.status_every_s,
            lan_beacon: crate::announce::should_announce(bound),
        };
        print!("{}", crate::operator::ready_card(&facts, style));
    }
    let mut pulse = options
        .overview
        .map(|_| crate::operator::PulseClock::new(options.status_every_s));
    let _beacon = crate::announce::should_announce(bound)
        .then(|| AbortOnDrop(tokio::spawn(crate::announce::broadcast_loop(bound.port()))));
    if let Some(tx) = ready {
        let _ = tx.send(bound);
    }

    if !session.state.map.is_authored() {
        tracing::info!(
            target: crate::logging::STARTUP_TARGET,
            "Rules: {}",
            session.state.config.rules.name()
        );
    }
    // The head-to-head book is arcade only: a campaign party has no frags
    // between callsigns to keep.
    let head_to_head = options
        .head_to_head
        .clone()
        .filter(|_| !session.state.map.is_campaign());
    if let Some(path) = head_to_head.as_deref() {
        let (book, refused) = crate::statistics::HeadToHead::load(path);
        if let Some(reason) = refused {
            tracing::warn!(
                "Head-to-head book refused ({reason}); starting a fresh one. The next save replaces the file."
            );
        }
        session.state.head_to_head = book;
    }
    let mut head_to_head_warned = false;
    session.spawn_bots(options.bots);
    if options.authored.is_none() && !options.campaign_run {
        tracing::info!(
            target: crate::logging::STARTUP_TARGET,
            "{}",
            crate::preflight::population_note(
                session.bots.len(),
                crate::net::connection_cap(),
                crate::net::address_cap(),
            )
        );
    }
    if options.solo_broadcast {
        session.enable_solo_broadcast_ep0();
        tracing::info!("Solo Broadcast Episode 0 armed (Calibration / Larak Lot)");
    }
    tracing::info!(
        target: crate::logging::STARTUP_TARGET,
        "Map: {} (id {}){}",
        session.state.map.name(),
        session.state.map.id(),
        if playlist {
            ", night playlist"
        } else if options.map_rotate {
            ", rotate each round"
        } else {
            ""
        }
    );

    let mut tick_interval = tokio::time::interval(TICK);
    tick_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut stats = crate::bench::TickStats::new();
    // The overview's pulse replaces the STATUS JSON line on a terminal.
    let mut status_interval =
        (options.status_every_s > 0 && options.overview.is_none()).then(|| {
            let mut i = tokio::time::interval(Duration::from_secs(options.status_every_s));
            i.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
            i
        });
    tracing::info!(
        target: crate::logging::STARTUP_TARGET,
        "Simulation seed: {}",
        options.seed
    );

    tracing::info!(
        target: crate::logging::STARTUP_TARGET,
        "Game loop starting (20 Hz tick)"
    );

    let mut desk_rx = None;
    let desk_task = if desk_wanted {
        match spawn_venue_desk(options.access.ban_list.clone()) {
            Ok((calls, task)) => {
                desk_rx = Some(calls);
                Some(AbortOnDrop(task))
            }
            Err(error) => {
                tracing::warn!("Venue desk did not open: {error}. The match continues.");
                None
            }
        }
    } else {
        if options.console {
            tracing::warn!(
                "Venue desk is only for a dedicated arcade match. The match continues without it."
            );
        }
        None
    };

    tokio::pin!(shutdown);

    loop {
        tokio::select! {
            deadline = tick_interval.tick() => {
                let started = std::time::Instant::now();
                let started_unix = tick_trace.is_some().then(std::time::SystemTime::now);
                let expired = session.resume.expire(session.state.tick);
                for player_id in expired {
                    session.drop_expired_pawn(player_id);
                }
                let messages = session.tick_messages(TICK.as_secs_f32());
                persist_local_run(&session.state, durable_run.as_mut())?;
                if session.state.round_state == crate::sim::RoundState::Ended {
                    save_head_to_head(&mut session.state, head_to_head.as_deref(), &mut head_to_head_warned);
                }
                session.resume.note_tick(session.state.tick);
                let elapsed = started.elapsed();
                let broadcasts = crate::net::Broadcast::encode_all(messages)?;
                let bytes: usize = broadcasts.iter().map(|broadcast| broadcast.text().len()).sum();
                let measured = started.elapsed();
                stats.record_tick(elapsed, bytes);
                let fanout_started = std::time::Instant::now();
                // Booth facts reach only the connections that watch.
                let watchers = if broadcasts
                    .iter()
                    .any(|broadcast| broadcast.audience() == crate::net::Audience::Spectators)
                {
                    session.spectator_ids()
                } else {
                    std::collections::HashSet::new()
                };
                let delivery = broadcast_to_clients(&clients, &broadcasts, &watchers).await;
                let broadcast_elapsed = fanout_started.elapsed();
                let connections;
                {
                    let now = std::time::Instant::now();
                    let clients_lock = clients.lock().await;
                    connections = clients_lock.len();
                    let refreshed = tracker.due(now);
                    if refreshed {
                        let pings: Vec<(uuid::Uuid, u16)> = clients_lock
                            .iter()
                            .filter_map(|client| Some((client.id, client.traffic().ping_ms()?)))
                            .collect();
                        session.note_pings(&pings);
                        let samples: Vec<crate::metrics::ClientSample<'_>> = clients_lock
                            .iter()
                            .map(|client| crate::metrics::ClientSample {
                                id: client.id,
                                traffic: client.traffic(),
                                queue_depth: client.queue_depth(),
                            })
                            .collect();
                        tracker.refresh(now, &samples);
                    }
                    drop(clients_lock);
                    let mut next = session.state.live_status(connections);
                    tracker.apply(&mut next, now);
                    // The tracker does not know the match. The sheet does.
                    if let Some(ops) = next.ops.as_mut() {
                        ops.night = session.sheet.totals();
                    }
                    // Once a second, with the snapshot `/status` serves.
                    if let (Some(clock), Some(style), true) = (pulse.as_mut(), options.overview, refreshed) {
                        if clock.due(now, &next) {
                            println!("{}", crate::operator::pulse_line(&next, crate::metrics::process_uptime(), style));
                        }
                    }
                    if let Ok(mut slot) = live.try_write() {
                        *slot = next;
                    }
                }
                let passes = session.take_seat_passes();
                if !passes.is_empty() {
                    let clients_lock = clients.lock().await;
                    for client in clients_lock.iter().filter(|client| passes.contains(&client.id)) {
                        client.seat_passed();
                    }
                }
                let unicasts = session.take_unicasts();
                let unicast_started = std::time::Instant::now();
                let unicast_delivery = send_unicasts(&clients, &session.client_to_player, &unicasts).await;
                let fanout_elapsed = broadcast_elapsed.saturating_add(unicast_started.elapsed());
                let finished = std::time::Instant::now();
                tracker.record_overflows(finished, delivery.queue_overflows + unicast_delivery.queue_overflows);
                tracker.record_tick(finished, finished.saturating_duration_since(started));
                if let (Some(trace), Some(started_unix)) = (tick_trace.as_mut(), started_unix) {
                    let deadline = deadline.into_std();
                    let skipped = trace.deadline(deadline);
                    trace.record(tick_sample(TickTraceInput {
                        messages: &broadcasts,
                        fallback_tick: session.state.tick,
                        started_unix,
                        late: started.saturating_duration_since(deadline),
                        skipped,
                        sim: elapsed,
                        measure: measured.saturating_sub(elapsed),
                        fanout: fanout_elapsed,
                        total: finished.saturating_duration_since(started),
                        clients: connections,
                        bytes,
                        overflows: delivery.queue_overflows + unicast_delivery.queue_overflows,
                    }));
                }
                if let Some(metrics) = &metrics {
                    let mut metrics = metrics.lock().unwrap_or_else(|poison| poison.into_inner());
                    metrics.session_ns.record(elapsed.as_nanos().min(u64::MAX as u128) as u64);
                    let encode = measured.saturating_sub(elapsed);
                    metrics.broadcast_encode_ns.record(encode.as_nanos().min(u64::MAX as u128) as u64);
                    metrics.fanout_ns.record(fanout_elapsed.as_nanos().min(u64::MAX as u128) as u64);
                    metrics.record_schedule(deadline.into_std(), started, finished.saturating_duration_since(started));
                    if let Some(tick) = snapshot_tick(&broadcasts) {
                        metrics.record_tick_start(tick, started);
                    }
                    metrics.record_delivery(delivery);
                    metrics.record_delivery(unicast_delivery);
                }
            }

            _ = async { status_interval.as_mut().expect("guarded").tick().await },
                if status_interval.is_some() && stats.ticks() > 0 =>
            {
                let fighters = session.state.players.iter().filter(|p| p.is_participant()).count();
                let client_count = clients.lock().await.len();
                let report = stats.report(fighters, client_count);
                match serde_json::to_string(&report) {
                    Ok(json) => tracing::info!("STATUS {json}"),
                    Err(err) => tracing::warn!("status report could not be encoded: {err}"),
                }
            }

            Some(call) = async { desk_rx.as_mut().expect("guarded").recv().await }, if desk_rx.is_some() => {
                let outcome = match call.verb {
                    crate::desk::DeskVerb::Status => {
                        let who = session.desk(crate::desk::DeskVerb::Who);
                        let snapshot = live.read().await.clone();
                        let style = crate::operator::Style { ansi: false };
                        crate::desk::DeskOutcome::Text(crate::operator::desk_status(
                            &crate::operator::pulse_line(&snapshot, crate::metrics::process_uptime(), style),
                            &joins,
                            who.text(),
                        ))
                    }
                    verb => session.desk(verb),
                };
                if let crate::desk::DeskOutcome::Close { client_id, banned, .. } = &outcome {
                    let clients_lock = clients.lock().await;
                    if let Some(client) = clients_lock.iter().find(|client| client.id == *client_id) {
                        client.venue_close(*banned);
                    }
                }
                let _ = call.reply.send(outcome);
                persist_local_run(&session.state, durable_run.as_mut())?;
            }

            Some(cmd) = game_rx.recv() => {
                if let crate::net::GameCommand::CancelAutoJoin { client_id } = &cmd {
                    clients.lock().await.retain(|client| client.id != *client_id);
                }
                session.apply_command(cmd);
                for (player_id, action) in game_tx.take_pending_actions() {
                    session.apply_command(crate::net::GameCommand::Action { player_id, action });
                }
                persist_local_run(&session.state, durable_run.as_mut())?;
                let unicasts = session.take_unicasts();
                let delivery = send_unicasts(&clients, &session.client_to_player, &unicasts).await;
                tracker.record_overflows(std::time::Instant::now(), delivery.queue_overflows);
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
    save_head_to_head(
        &mut session.state,
        head_to_head.as_deref(),
        &mut head_to_head_warned,
    );
    if let Some(trace) = tick_trace.take() {
        match trace.finish() {
            Ok(summary) => tracing::info!(
                "Tick trace complete: {} ticks, {} over budget, {} skipped periods, {} dropped",
                summary.ticks,
                summary.over_budget,
                summary.skipped_periods,
                summary.dropped
            ),
            Err(error) => tracing::warn!("Tick trace did not finish cleanly: {error}"),
        }
    }
    drop(desk_task);
    drop(access_reload);
    // The listener belongs to this runner. Normal shutdown observes its
    // retirement; early returns still schedule abort through the owning guard.
    accept_task.0.abort();
    let _ = (&mut accept_task.0).await;

    Ok(())
}

fn spawn_venue_desk(
    ban_list: Option<PathBuf>,
) -> std::io::Result<(
    mpsc::UnboundedReceiver<crate::desk::DeskCall>,
    tokio::task::JoinHandle<()>,
)> {
    let (line_tx, line_rx) = mpsc::unbounded_channel();
    let (call_tx, call_rx) = mpsc::unbounded_channel();
    // A blocked read must not sit on the async runtime. Dropping this handle
    // detaches the thread; process exit does not wait for it.
    std::thread::Builder::new()
        .name("venue-desk".into())
        .spawn(move || {
            let stdin = std::io::stdin();
            let mut line = String::new();
            loop {
                line.clear();
                match stdin.read_line(&mut line) {
                    Ok(0) | Err(_) => break,
                    Ok(_) => {
                        if line_tx.send(line.clone()).is_err() {
                            break;
                        }
                    }
                }
            }
        })?;
    let task = tokio::spawn(async move {
        println!(
            "Venue desk. help, status, who, kick <name>, ban <name> [reason], say <sentence>, stats, shows, next, map <map> <mode>. Closing this input leaves the match running."
        );
        let mut out = std::io::stdout();
        crate::desk::serve(line_rx, call_tx, ban_list, &mut out).await;
        println!("Venue desk closed. The match keeps running.");
    });
    Ok((call_rx, task))
}

/// What the tick loop measured, before it becomes one trace record.
struct TickTraceInput<'a> {
    messages: &'a [std::sync::Arc<crate::net::Broadcast>],
    fallback_tick: u64,
    started_unix: std::time::SystemTime,
    late: Duration,
    skipped: u64,
    sim: Duration,
    measure: Duration,
    fanout: Duration,
    total: Duration,
    clients: usize,
    bytes: usize,
    overflows: u64,
}

/// The tick number clients see on this tick's Snapshot, if it built one.
fn snapshot_tick(messages: &[std::sync::Arc<crate::net::Broadcast>]) -> Option<u64> {
    messages.iter().find_map(|message| match message.message() {
        crate::protocol::ServerMessage::Snapshot(snapshot) => Some(snapshot.tick),
        _ => None,
    })
}

/// The record names the Snapshot tick the clients receive, so a client trace
/// joins on it. A tick without a Snapshot keeps the session's own counter.
fn tick_sample(input: TickTraceInput<'_>) -> crate::tick_trace::TickSample {
    use crate::tick_trace::micros;
    let tick = snapshot_tick(input.messages).unwrap_or(input.fallback_tick);
    crate::tick_trace::TickSample {
        tick,
        unix_us: crate::tick_trace::unix_micros(input.started_unix),
        late_us: micros(input.late),
        skipped: input.skipped,
        sim_us: micros(input.sim),
        measure_us: micros(input.measure),
        fanout_us: micros(input.fanout),
        total_us: micros(input.total),
        clients: u32::try_from(input.clients).unwrap_or(u32::MAX),
        messages: u32::try_from(input.messages.len()).unwrap_or(u32::MAX),
        bytes: u64::try_from(input.bytes).unwrap_or(u64::MAX),
        overflows: input.overflows,
    }
}

/// Ends an owned background task with the loop, including early error returns.
struct AbortOnDrop(tokio::task::JoinHandle<()>);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

/// Save the head-to-head book when it has changed. A failed save keeps the
/// book in memory and warns once; the match never stops for it.
fn save_head_to_head(state: &mut crate::sim::GameState, path: Option<&Path>, warned: &mut bool) {
    let Some(path) = path else { return };
    if !state.head_to_head.is_dirty() || *warned {
        return;
    }
    if let Err(error) = state.head_to_head.save(path) {
        *warned = true;
        tracing::warn!(
            "Head-to-head book could not be saved to {}: {error}. It is kept for this session only.",
            path.display()
        );
    }
}

fn persist_local_run(
    state: &crate::sim::GameState,
    run: Option<&mut DurableRun>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    run.map_or(Ok(()), |run| run.persist(state))
}

/// The one durable local run: the writer lock on `run.json`, how a session
/// opens a new run or resumes a saved one, and the write after each change.
/// The local child uses it, and in-process harnesses reach the same disk path
/// through it instead of a second save API.
pub struct DurableRun {
    store: RunStore,
    last: Option<RunDocument>,
}

impl DurableRun {
    /// Open `directory` for `session` before anyone is admitted. A new run
    /// must start at M01 and writes its initial document. A resume loads the
    /// saved entry or pending Continue, first promoting a saved departure
    /// into the next mission and writing that promotion.
    pub fn open(
        session: &mut GameSession,
        directory: &Path,
        resume: bool,
        difficulty: Option<CampaignDifficulty>,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let content_sha256 = session
            .state
            .map
            .content_sha256()
            .ok_or("durable local run requires authored content")?;
        let current = session.state.map.campaign_mission_id();
        let hashes: crate::mission::run_file::store::ContentHashes = std::array::from_fn(|index| {
            let mission = crate::mission::run_file::store::CAMPAIGN_MISSIONS[index];
            if current == Some(mission) {
                content_sha256
            } else {
                crate::maps::AuthoredSource::bundled_content_sha256(mission)
            }
        });
        let store = RunStore::open_with_hashes(directory, hashes)?;
        let last = if resume {
            let mut saved = store.load()?.ok_or("no saved campaign run to resume")?;
            let target = current.ok_or("missing mission identity")?;
            if matches!(
                saved.step,
                crate::mission::run_file::SavedStep::AwaitingMission { .. }
            ) {
                if target == crate::protocol::MissionId::RecallNotice {
                    return Err("a saved transition cannot return to M01".into());
                }
                // Entering the next mission is the one gameplay transition a
                // resume writes: carried outcomes, refills and entry stock.
                saved = saved.promote_next(
                    target,
                    hashes[crate::mission::run_file::store::stage_index(target)],
                )?;
                store.save(&saved)?;
            } else if saved.stage_mission() != target {
                return Err("saved campaign run names another mission".into());
            }
            if !matches!(
                saved.step,
                crate::mission::run_file::SavedStep::MissionEntry { .. }
                    | crate::mission::run_file::SavedStep::PendingContinue { .. }
            ) {
                return Err("saved campaign run is not playable".into());
            }
            session.state.load_campaign_run(&saved)?;
            saved
        } else {
            if current != Some(crate::protocol::MissionId::RecallNotice) {
                return Err("new durable run must start at M01".into());
            }
            session
                .state
                .set_campaign_difficulty(difficulty.unwrap_or_default())?;
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
            store.save(&initial)?;
            initial
        };
        Ok(Self {
            store,
            last: Some(last),
        })
    }

    /// Write the session's current run document when it has changed.
    pub fn persist(
        &mut self,
        state: &crate::sim::GameState,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let Some(document) = state.campaign_run_document()? else {
            return Ok(());
        };
        if self.last.as_ref() != Some(&document) {
            self.store.save(&document)?;
            self.last = Some(document);
        }
        Ok(())
    }
}

#[cfg(test)]
mod head_to_head_tests {
    use super::save_head_to_head;
    use crate::sim::GameState;

    #[test]
    fn a_changed_book_is_saved_once_and_a_failed_save_warns_once() {
        let directory = std::env::temp_dir().join(format!(
            "fragr-run-book-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        let path = directory.join("head-to-head.json");
        let mut state = GameState::new();
        let mut warned = false;
        // No path: nothing is written and nothing is said.
        state.head_to_head.record("Nightfall", "Pi");
        save_head_to_head(&mut state, None, &mut warned);
        assert!(state.head_to_head.is_dirty() && !warned);
        save_head_to_head(&mut state, Some(&path), &mut warned);
        assert!(!state.head_to_head.is_dirty() && !warned);
        let (book, refused) = crate::statistics::HeadToHead::load(&path);
        assert_eq!((book.frags("Nightfall", "Pi"), refused), (1, None));
        // Unchanged since: no second write.
        std::fs::remove_file(&path).unwrap();
        save_head_to_head(&mut state, Some(&path), &mut warned);
        assert!(!path.exists());
        // A path that cannot be written keeps the book in memory and warns once.
        std::fs::create_dir_all(&path).unwrap();
        state.head_to_head.record("Pi", "Nightfall");
        save_head_to_head(&mut state, Some(&path), &mut warned);
        assert!(warned && state.head_to_head.is_dirty());
        assert_eq!(state.head_to_head.frags("Pi", "Nightfall"), 1);
        std::fs::remove_dir_all(&directory).unwrap();
    }
}

#[cfg(test)]
mod durable_run_tests {
    use super::DurableRun;
    use crate::maps::AuthoredSource;
    use crate::protocol::{CampaignDifficulty, MissionId, Role};
    use crate::session::GameSession;

    fn session(mission: MissionId) -> GameSession {
        GameSession::with_authored_map(AuthoredSource::Mission(mission).load().unwrap())
    }

    fn refusal(result: Result<DurableRun, Box<dyn std::error::Error + Send + Sync>>) -> String {
        result.err().unwrap().to_string()
    }

    #[test]
    fn one_run_file_opens_new_resumes_locks_and_writes_only_changes() {
        let directory =
            std::env::temp_dir().join(format!("fragr-durable-run-{}", uuid::Uuid::new_v4()));
        let mut m02 = session(MissionId::PersonsUnknown);
        assert_eq!(
            refusal(DurableRun::open(&mut m02, &directory, true, None)),
            "no saved campaign run to resume"
        );
        assert_eq!(
            refusal(DurableRun::open(&mut m02, &directory, false, None)),
            "new durable run must start at M01"
        );
        let mut m01 = session(MissionId::RecallNotice);
        let mut run = DurableRun::open(
            &mut m01,
            &directory,
            false,
            Some(CampaignDifficulty::Severe),
        )
        .unwrap();
        assert_eq!(
            m01.state.campaign_rules().difficulty,
            CampaignDifficulty::Severe
        );
        // The writer lock refuses a second owner of the same directory.
        let mut second = session(MissionId::RecallNotice);
        assert!(DurableRun::open(&mut second, &directory, true, None).is_err());
        // An unchanged document is not written again; a changed one is.
        std::fs::remove_file(directory.join("run.json")).unwrap();
        run.persist(&m01.state).unwrap();
        assert!(!directory.join("run.json").exists());
        m01.state
            .add_player(uuid::Uuid::from_u128(1), "Owner".into(), Role::Human);
        run.persist(&m01.state).unwrap();
        assert!(directory.join("run.json").exists());
        drop(run);
        let mut m01 = session(MissionId::RecallNotice);
        DurableRun::open(&mut m01, &directory, true, None).unwrap();
        assert_eq!(
            m01.state.campaign_rules().difficulty,
            CampaignDifficulty::Severe
        );
        let mut m02 = session(MissionId::PersonsUnknown);
        assert_eq!(
            refusal(DurableRun::open(&mut m02, &directory, true, None)),
            "saved campaign run names another mission"
        );
        std::fs::remove_dir_all(&directory).unwrap();
    }
}

#[cfg(test)]
mod metrics_tests {
    use super::{RunMetrics, TICK};
    use std::time::Duration;

    #[test]
    fn measured_ticks_count_lateness_skips_and_budget() {
        let mut metrics = RunMetrics::default();
        let first = std::time::Instant::now();
        metrics.record_schedule(
            first,
            first + Duration::from_millis(2),
            Duration::from_millis(4),
        );
        // The next deadline is three periods on: two were skipped.
        let late = first + TICK * 3;
        metrics.record_schedule(late, late + Duration::from_millis(10), TICK);
        let report = metrics.report();
        assert_eq!(report.tick_ms.count, 2);
        assert_eq!(report.late_ms.count, 2);
        assert!(report.late_ms.max >= 10.0 && report.late_ms.max < 11.0);
        assert_eq!(report.skipped_periods, 2);
        assert_eq!(report.over_budget, 1);
        // A measured window starts clean but keeps the deadline chain.
        metrics.reset();
        let next = late + TICK;
        metrics.record_schedule(next, next, Duration::from_millis(1));
        let report = metrics.report();
        assert_eq!((report.skipped_periods, report.over_budget), (0, 0));
        assert_eq!(report.tick_ms.count, 1);
    }
}
