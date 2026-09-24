//! Game session: join/leave/action command application and tick broadcast.
//! Extracted from the binary so join/leave/round wire paths are unit-testable.

use crate::net::{ClientSession, GameCommand};
use crate::protocol::{self, Role, ServerMessage};
use crate::resume::ResumeTable;
use crate::sim::{BotController, GameState, MapKind, SpeakOutcome};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

/// Connections include spectators, which have no player identity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Recipient {
    Client(Uuid),
    Player(Uuid),
}

/// Owns sim state, bot controllers, and client-to-player mapping for the arena.
pub struct GameSession {
    pub state: GameState,
    pub bots: Vec<BotController>,
    pub client_to_player: HashMap<Uuid, Uuid>,
    /// Targeted control messages, drained by the game loop.
    pub pending_unicasts: Vec<(Recipient, ServerMessage)>,
    /// The map the last MapInfo described, so a rotation resends it once.
    last_map_sent: Option<crate::maps::RuntimeMap>,
    last_mission_sent: Option<protocol::MissionState>,
    /// Target rule-bot count. Solo scrap and empty-arena recovery refill up to this.
    pub min_bots: usize,
    navigation_map: crate::maps::RuntimeMap,
    navigators: HashMap<Uuid, crate::navigation::Navigator>,
    sent_loadouts: HashMap<Uuid, (crate::protocol::WeaponType, u64)>,
    sent_records: HashMap<Uuid, protocol::PlayerRecord>,
    pub resume: Arc<ResumeTable>,
}

impl GameSession {
    pub fn new() -> Self {
        Self::with_map(MapKind::ArenaDuel, false)
    }

    pub fn with_map(map: MapKind, map_rotate: bool) -> Self {
        crate::maps::prepare_navigation(map, map_rotate);
        Self::with_state(GameState::with_map(map, map_rotate))
    }

    pub fn with_authored_map(map: Arc<crate::maps::AuthoredMap>) -> Self {
        Self::with_state(GameState::with_authored_map(map))
    }

    fn with_state(state: GameState) -> Self {
        Self {
            navigation_map: state.map.clone(),
            state,
            bots: Vec::new(),
            client_to_player: HashMap::new(),
            pending_unicasts: Vec::new(),
            last_map_sent: None,
            last_mission_sent: None,
            min_bots: 0,
            navigators: HashMap::new(),
            sent_loadouts: HashMap::new(),
            sent_records: HashMap::new(),
            resume: Arc::new(ResumeTable::new()),
        }
    }

    /// Contested Frequency scrap-league rule-bot roster (callsigns + sticky behaviors).
    pub fn rule_bot_roster() -> &'static [(&'static str, crate::sim::BotBehavior)] {
        &[
            ("Dead Air Dan", crate::sim::BotBehavior::Aggressive),
            ("Nightfall", crate::sim::BotBehavior::Defensive),
            ("Static Kid", crate::sim::BotBehavior::Flanker),
            ("Aunt Linda", crate::sim::BotBehavior::Balanced),
            ("Scout Ant", crate::sim::BotBehavior::Flanker),
            ("Crackpot", crate::sim::BotBehavior::Defensive),
            ("Buzzkill", crate::sim::BotBehavior::Aggressive),
            ("Tin Foil Tina", crate::sim::BotBehavior::Balanced),
        ]
    }

    /// Spawn named scrap bots into the arena (same configs as the production binary).
    /// Raises `min_bots` to at least the resulting rule-bot count so solo stays stocked.
    /// Refreshes sticky Warmup Host roster intro for mid-join.
    pub fn spawn_bots(&mut self, count: usize) {
        let bot_configs = Self::rule_bot_roster();

        let start_index = self.bots.len();
        for i in 0..count {
            let bot_id = self.state.new_entity_id();
            let config_index = start_index + i;
            let (bot_name, behavior) = bot_configs
                .get(config_index % bot_configs.len())
                .copied()
                .unwrap_or(("Scrap Bot", crate::sim::BotBehavior::Balanced));
            let display_name = if config_index < bot_configs.len() {
                bot_name.to_string()
            } else {
                format!("{bot_name}-{}", config_index / bot_configs.len() + 1)
            };
            self.state
                .add_player(bot_id, display_name.clone(), Role::Agent);
            let bot_controller = BotController::new(bot_id, behavior);
            self.bots.push(bot_controller.clone());
            self.state.bots.push(bot_controller);
            tracing::info!("Spawned bot: {} ({:?}, {})", display_name, behavior, bot_id);
        }
        if self.bots.len() > self.min_bots {
            self.min_bots = self.bots.len();
        }
        if let Some(mission) = self.state.mission_state() {
            for bot in &self.bots[start_index..] {
                self.state.acknowledge_mission(
                    bot.player_id,
                    protocol::MissionReady {
                        id: mission.id,
                        attempt: mission.attempt,
                    },
                );
            }
        }
        self.refresh_roster_host_line();
    }

    /// Arm Solo Broadcast Episode 0 after bots are spawned (Calibration / Larak Lot).
    pub fn enable_solo_broadcast_ep0(&mut self) {
        self.state.enable_solo_broadcast_ep0();
        self.refresh_roster_host_line();
    }

    /// Rebuild sticky Warmup Host line from current rule-bot display names.
    fn refresh_roster_host_line(&mut self) {
        let names: Vec<String> = self
            .bots
            .iter()
            .filter_map(|b| {
                self.state
                    .players
                    .iter()
                    .find(|p| p.id == b.player_id)
                    .map(|p| p.name.clone())
            })
            .collect();
        self.state.set_roster_host_line_from_names(&names);
    }

    /// Set the floor for rule-bot count and refill immediately if below it.
    pub fn set_min_bots(&mut self, min_bots: usize) {
        self.min_bots = min_bots;
        self.ensure_min_bots();
    }

    /// Spawn rule bots until `bots.len() >= min_bots`. No-op when already stocked or min is 0.
    pub fn ensure_min_bots(&mut self) {
        if self.min_bots == 0 {
            return;
        }
        let have = self.bots.len();
        if have >= self.min_bots {
            return;
        }
        let need = self.min_bots - have;
        tracing::info!(
            "Arena below min_bots ({have}/{}); spawning {need} rule bot(s)",
            self.min_bots
        );
        self.spawn_bots(need);
    }

    /// Names are display labels, never credentials for reclaiming another seat.
    fn available_display_name(&self, requested: &str) -> String {
        let cleaned: String = requested.chars().filter(|c| !c.is_control()).collect();
        let mut base: String = cleaned.trim().chars().take(24).collect();
        if base.is_empty() {
            base = "Player".to_string();
        }
        let mut candidate = base.clone();
        let mut suffix = 2_u64;
        while self
            .state
            .players
            .iter()
            .any(|player| player.name == candidate)
        {
            candidate = format!("{base} #{suffix}");
            suffix += 1;
        }
        candidate
    }

    fn remove_pawn(&mut self, player_id: Uuid) {
        let (player_name, player_score) = self
            .state
            .players
            .iter()
            .find(|p| p.id == player_id)
            .map(|p| (p.name.clone(), *self.state.scores.get(&p.id).unwrap_or(&0)))
            .unwrap_or_else(|| ("Unknown".to_string(), 0));
        let player_count_before = self
            .state
            .players
            .iter()
            .filter(|p| !p.is_campaign_enemy())
            .count();
        self.state.remove_player(player_id);
        self.state.push_event(protocol::GameEvent::PlayerLeft {
            player: player_name.clone(),
            score: player_score,
            round_number: self.state.round_number,
            player_count: player_count_before.saturating_sub(1),
        });
        tracing::info!(
            "Player {} left (score: {}, round {}, {} players remain)",
            player_name,
            player_score,
            self.state.round_number,
            player_count_before.saturating_sub(1)
        );
    }

    /// Grace ended. A client that already rebound this pawn is left alone.
    pub fn drop_expired_pawn(&mut self, player_id: Uuid) {
        if self.client_to_player.values().any(|id| *id == player_id) {
            return;
        }
        if self
            .state
            .players
            .iter()
            .any(|player| player.id == player_id)
        {
            self.remove_pawn(player_id);
        }
    }

    fn resume_pawn(
        &mut self,
        client_id: Uuid,
        player_id: Uuid,
        nonce: u64,
        role: Role,
    ) -> Option<crate::resume::ResumeAccept> {
        let player = self
            .state
            .players
            .iter()
            .find(|player| player.id == player_id)?;
        if player.role != role || player.is_campaign_enemy() {
            return None;
        }
        let accepted = self.resume.claim(player_id, nonce, role)?;
        self.client_to_player.retain(|_, id| *id != player_id);
        self.client_to_player.insert(client_id, player_id);
        if let Some(player) = self.state.players.iter_mut().find(|p| p.id == player_id) {
            player.clear_input();
        }
        self.pending_unicasts
            .push((Recipient::Client(client_id), self.state.map_info()));
        if let Some(message) = self.state.mission_message() {
            self.pending_unicasts
                .push((Recipient::Client(client_id), message));
        }
        Some(accepted)
    }

    /// Apply a net-layer game command (join, leave, or action).
    /// Join/leave push PlayerJoined / PlayerLeft events onto the sim event queue.
    pub fn apply_command(&mut self, cmd: GameCommand) {
        match cmd {
            GameCommand::Connected {
                id,
                role,
                name,
                player_id,
            } => {
                // Every connection needs geometry, including late spectators.
                self.pending_unicasts
                    .push((Recipient::Client(id), self.state.map_info()));
                if let Some(pid) = player_id {
                    let name = self.available_display_name(&name);
                    self.state.add_player(pid, name.clone(), role);
                    if !self.state.players.iter().any(|player| player.id == pid) {
                        self.pending_unicasts.push((
                            Recipient::Client(id),
                            ServerMessage::Error {
                                code: "run_seat_closed".into(),
                                message: "The campaign run already has an owner.".into(),
                            },
                        ));
                        return;
                    }
                    self.client_to_player.insert(id, pid);
                    let player_count = self
                        .state
                        .players
                        .iter()
                        .filter(|p| !p.is_campaign_enemy())
                        .count();
                    self.state.push_event(protocol::GameEvent::PlayerJoined {
                        player: name.clone(),
                        role: format!("{:?}", role).to_lowercase(),
                        round_number: self.state.round_number,
                        player_count,
                    });
                    tracing::info!(
                        "Player {} joined as {:?} (round {}, {} players)",
                        pid,
                        role,
                        self.state.round_number,
                        player_count
                    );
                } else {
                    tracing::info!("Spectator {} joined", name);
                }
                if let Some(message) = self.state.mission_message() {
                    self.pending_unicasts.push((Recipient::Client(id), message));
                }
            }

            GameCommand::Disconnected { id } => {
                if let Some(player_id) = self.client_to_player.remove(&id) {
                    self.remove_pawn(player_id);
                }
            }
            GameCommand::Detached { id } => {
                if let Some(player_id) = self.client_to_player.remove(&id) {
                    if let Some(player) = self.state.players.iter_mut().find(|p| p.id == player_id)
                    {
                        player.clear_input();
                    }
                }
            }
            GameCommand::Resume {
                client_id,
                player_id,
                nonce,
                role,
                reply,
            } => {
                let _ = reply.send(self.resume_pawn(client_id, player_id, nonce, role));
            }

            GameCommand::Action { player_id, action } => {
                self.state.set_action(player_id, action);
            }

            GameCommand::MissionReady { player_id, ready } => {
                self.state.acknowledge_mission(player_id, ready);
            }
            GameCommand::MissionContinue { player_id, request } => {
                if !self.state.continue_mission(player_id, request) {
                    self.pending_unicasts.push((
                        Recipient::Player(player_id),
                        ServerMessage::Error {
                            code: "continue_rejected".into(),
                            message: "Continue is unavailable or refers to a previous attempt."
                                .into(),
                        },
                    ));
                }
            }

            GameCommand::Speak { player_id, text } => {
                match self.state.try_speak(player_id, &text) {
                    SpeakOutcome::Sent => {}
                    SpeakOutcome::RateLimited => {
                        self.pending_unicasts.push((
                            Recipient::Player(player_id),
                            ServerMessage::Error {
                                code: "speak_rate_limited".to_string(),
                                message: "speak rate limited; try again in a few seconds"
                                    .to_string(),
                            },
                        ));
                    }
                    SpeakOutcome::Rejected => {
                        self.pending_unicasts.push((
                            Recipient::Player(player_id),
                            ServerMessage::Error {
                                code: "speak_rejected".to_string(),
                                message: "speak rejected".to_string(),
                            },
                        ));
                    }
                }
            }

            GameCommand::SetDisplayBehavior {
                player_id,
                behavior,
            } => {
                let _ = self.state.set_display_behavior(player_id, &behavior);
            }
        }
    }

    /// Run one sim tick: bot AI, physics, then collect snapshot + event messages to broadcast.
    pub fn tick_messages(&mut self, dt: f32) -> Vec<ServerMessage> {
        self.ensure_min_bots();
        if self.navigation_map != self.state.map {
            self.navigation_map = self.state.map.clone();
            self.navigators.clear();
        }
        let map = self.state.map.clone();
        let world = map.navigation();
        let mut driven = std::collections::HashSet::new();
        let mut controllers = self.bots.clone();
        for bot in &controllers {
            driven.insert(bot.player_id);
        }
        // Continuance boss lives on GameState.bots only (not min_bots roster).
        controllers.extend(
            self.state
                .bots
                .iter()
                .filter(|b| !driven.contains(&b.player_id))
                .cloned(),
        );
        driven.extend(controllers.iter().map(|bot| bot.player_id));
        let enemies = self.state.enemy_intents();
        driven.extend(enemies.iter().map(|(id, _)| *id));
        self.navigators.retain(|id, _| driven.contains(id));
        // At most four searches per tick, with rotating slots so larger rosters
        // cannot starve their later controllers. Cached paths keep advancing.
        let batches = (controllers.len() + enemies.len()).div_ceil(4).max(1);
        let discovery = (map.equipment_policy() == protocol::EquipmentPolicy::Discovery)
            .then(|| self.state.snapshot());
        for (index, bot) in controllers.iter().enumerate() {
            let intent = bot.intent(&self.state);
            let action = if let Some(snapshot) = discovery.as_ref() {
                let loadout = self
                    .state
                    .players
                    .iter()
                    .find(|player| player.id == bot.player_id)
                    .and_then(|player| {
                        player
                            .inventory
                            .state(player.id, player.weapon, self.state.tick)
                    });
                let wanted = crate::inventory::control_action(
                    bot.player_id,
                    snapshot,
                    loadout.as_ref(),
                    intent.action,
                );
                self.navigators
                    .entry(bot.player_id)
                    .or_default()
                    .steer_snapshot_with_budget(
                        world,
                        bot.player_id,
                        snapshot,
                        wanted,
                        index / 4 == self.state.tick as usize % batches,
                    )
            } else if let (Some(goal), Some(player)) = (
                intent.goal,
                self.state
                    .players
                    .iter()
                    .find(|player| player.id == bot.player_id),
            ) {
                self.navigators.entry(bot.player_id).or_default().steer(
                    world,
                    [player.x, player.y - crate::sim::PLAYER_FLOOR_Y, player.z],
                    goal,
                    intent.action,
                    self.state.tick,
                    index / 4 == self.state.tick as usize % batches,
                )
            } else {
                self.navigators.remove(&bot.player_id);
                intent.action
            };
            self.state.set_action(bot.player_id, action);
        }

        for (index, (id, intent)) in enemies.into_iter().enumerate() {
            let action = if let (Some(goal), Some(player)) = (
                intent.goal,
                self.state.players.iter().find(|p| p.id == id && p.hp > 0),
            ) {
                self.navigators.entry(id).or_default().steer(
                    world,
                    [player.x, player.y - crate::sim::PLAYER_FLOOR_Y, player.z],
                    goal,
                    intent.action,
                    self.state.tick,
                    (controllers.len() + index) / 4 == self.state.tick as usize % batches,
                )
            } else {
                self.navigators.remove(&id);
                intent.action
            };
            self.state.set_action(id, action);
        }

        self.state.tick(dt);
        self.send_records();
        if self.state.map.equipment_policy() == protocol::EquipmentPolicy::Discovery {
            let connected: std::collections::HashSet<Uuid> =
                self.client_to_player.values().copied().collect();
            self.sent_loadouts.retain(|id, _| connected.contains(id));
            for player in &self.state.players {
                if !connected.contains(&player.id) {
                    continue;
                }
                let revision = (player.weapon, player.inventory.revision());
                if self.sent_loadouts.get(&player.id) != Some(&revision) {
                    self.sent_loadouts.insert(player.id, revision);
                    if let Some(loadout) =
                        player
                            .inventory
                            .state(player.id, player.weapon, self.state.tick)
                    {
                        self.pending_unicasts.push((
                            Recipient::Player(player.id),
                            ServerMessage::Loadout(loadout),
                        ));
                    }
                }
            }
        } else {
            self.sent_loadouts.clear();
        }
        self.pending_unicasts.extend(
            self.state
                .input_acks()
                .into_iter()
                .map(|(id, message)| (Recipient::Player(id), message)),
        );

        let mut out = Vec::new();
        // A mission gate also swaps immutable geometry. Send it before mission
        // state and snapshots so every controller observes the same world.
        if self.last_map_sent.as_ref() != Some(&self.state.map) {
            self.last_map_sent = Some(self.state.map.clone());
            self.last_mission_sent = None;
            out.push(self.state.map_info());
        }
        let mission = self.state.mission_state();
        if self.last_mission_sent != mission {
            if let Some(state) = mission.as_ref() {
                out.push(ServerMessage::Mission {
                    tick: self.state.tick,
                    state: state.clone(),
                });
            }
            self.last_mission_sent = mission;
        }
        out.push(ServerMessage::Snapshot(self.state.snapshot()));
        for event in self.state.take_events() {
            out.push(ServerMessage::Event(event));
        }
        out
    }

    /// Drain targeted messages queued by commands and the tick.
    pub fn take_unicasts(&mut self) -> Vec<(Recipient, ServerMessage)> {
        std::mem::take(&mut self.pending_unicasts)
    }

    fn send_records(&mut self) {
        let mut ids: Vec<Uuid> = self.client_to_player.values().copied().collect();
        ids.sort_unstable();
        self.sent_records
            .retain(|id, _| self.client_to_player.values().any(|p| p == id));
        for id in &ids {
            let Some(record) = self.state.player_record(*id) else {
                continue;
            };
            let send = self.sent_records.get(id).is_none_or(|old| {
                old.round != record.round
                    || old.status != record.status
                    || old.scope != record.scope
                    || (!record.status.terminal() && record.tick.saturating_sub(old.tick) >= 20)
            });
            if send {
                self.sent_records.insert(*id, record.clone());
                self.pending_unicasts
                    .push((Recipient::Player(*id), ServerMessage::Record(record)));
            }
        }
    }
}

impl Default for GameSession {
    fn default() -> Self {
        Self::new()
    }
}

/// Fan-out only after a connection's initial geometry has entered its FIFO.
#[derive(Debug, Default, Clone, Copy)]
pub struct DeliveryStats {
    pub queued_messages: u64,
    pub queue_high_water: usize,
    pub queue_overflows: u64,
}

fn queue_for_client(
    client: &mut ClientSession,
    msg: &ServerMessage,
    stats: &mut DeliveryStats,
) -> bool {
    if client.is_closing() {
        return false;
    }
    match client.tx.try_send(msg.clone()) {
        Ok(()) => {
            stats.queued_messages += 1;
            stats.queue_high_water = stats.queue_high_water.max(client.queue_depth());
            true
        }
        Err(error) => {
            if matches!(error, tokio::sync::mpsc::error::TrySendError::Full(_)) {
                stats.queue_overflows += 1;
                tracing::warn!(client = %client.id, "outbound queue full; disconnecting slow client");
            }
            client.request_close();
            false
        }
    }
}

pub async fn broadcast_to_clients(
    clients: &Arc<Mutex<Vec<ClientSession>>>,
    messages: &[ServerMessage],
) -> DeliveryStats {
    let mut stats = DeliveryStats::default();
    let mut clients_lock = clients.lock().await;
    for msg in messages {
        for client in clients_lock.iter_mut().filter(|client| client.initialized) {
            queue_for_client(client, msg, &mut stats);
        }
    }
    stats
}

/// Resolve connection or player recipients through the same delivery path.
pub async fn send_unicasts(
    clients: &Arc<Mutex<Vec<ClientSession>>>,
    client_to_player: &HashMap<Uuid, Uuid>,
    unicasts: &[(Recipient, ServerMessage)],
) -> DeliveryStats {
    let mut stats = DeliveryStats::default();
    if unicasts.is_empty() {
        return stats;
    }
    let mut clients_lock = clients.lock().await;
    for (recipient, msg) in unicasts {
        let client_id = match recipient {
            Recipient::Client(id) => Some(*id),
            Recipient::Player(player_id) => client_to_player
                .iter()
                .find(|(_, pid)| *pid == player_id)
                .map(|(cid, _)| *cid),
        };
        let Some(client_id) = client_id else {
            continue;
        };
        if let Some(client) = clients_lock.iter_mut().find(|c| c.id == client_id) {
            if matches!(msg, ServerMessage::Record(_))
                && client.gameplay_version < protocol::AMMO_GAMEPLAY_VERSION
            {
                continue;
            }
            if queue_for_client(client, msg, &mut stats)
                && matches!(msg, ServerMessage::MapInfo { .. })
            {
                client.initialized = true;
            }
        }
    }
    stats
}

#[cfg(test)]
mod session_tests {
    use super::*;
    use crate::protocol::Action;

    #[tokio::test]
    async fn only_successful_initial_geometry_delivery_enables_broadcasts() {
        let ids = [Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4()];
        let (pending_tx, mut pending_rx) = tokio::sync::mpsc::channel(2);
        let (active_tx, mut active_rx) = tokio::sync::mpsc::channel(2);
        let (closed_tx, closed_rx) = tokio::sync::mpsc::channel(2);
        drop(closed_rx);
        let clients = Arc::new(Mutex::new(vec![
            ClientSession::new(ids[0], pending_tx, protocol::GAMEPLAY_VERSION),
            ClientSession::new(ids[1], active_tx, protocol::GAMEPLAY_VERSION),
            ClientSession::new(ids[2], closed_tx, protocol::GAMEPLAY_VERSION),
        ]));
        let session = GameSession::new();
        let map = session.state.map_info();
        send_unicasts(
            &clients,
            &HashMap::new(),
            &[
                (Recipient::Client(ids[1]), map.clone()),
                (Recipient::Client(ids[2]), map.clone()),
            ],
        )
        .await;
        assert!(matches!(
            active_rx.try_recv().unwrap(),
            ServerMessage::MapInfo { .. }
        ));
        assert!(
            !clients.lock().await[2].initialized,
            "a failed send cannot initialize a connection"
        );
        let snapshot = ServerMessage::Snapshot(session.state.snapshot());
        broadcast_to_clients(&clients, std::slice::from_ref(&snapshot)).await;
        assert!(
            pending_rx.try_recv().is_err(),
            "broadcast overtook geometry"
        );
        assert!(matches!(
            active_rx.try_recv().unwrap(),
            ServerMessage::Snapshot(_)
        ));
        let error = ServerMessage::Error {
            code: "test".into(),
            message: "test".into(),
        };
        send_unicasts(
            &clients,
            &HashMap::new(),
            &[(Recipient::Client(ids[0]), error)],
        )
        .await;
        assert!(matches!(
            pending_rx.try_recv().unwrap(),
            ServerMessage::Error { .. }
        ));
        assert!(
            !clients.lock().await[0].initialized,
            "ordinary unicast cannot bypass initialization"
        );
        send_unicasts(
            &clients,
            &HashMap::new(),
            &[(Recipient::Client(ids[0]), map)],
        )
        .await;
        broadcast_to_clients(&clients, &[snapshot]).await;
        assert!(matches!(
            pending_rx.try_recv().unwrap(),
            ServerMessage::MapInfo { .. }
        ));
        assert!(matches!(
            pending_rx.try_recv().unwrap(),
            ServerMessage::Snapshot(_)
        ));
    }

    #[tokio::test]
    async fn full_initial_queue_closes_only_that_client_and_keeps_healthy_order() {
        let slow_id = Uuid::new_v4();
        let healthy_id = Uuid::new_v4();
        let (slow_tx, mut slow_rx) = tokio::sync::mpsc::channel(1);
        let (healthy_tx, mut healthy_rx) = tokio::sync::mpsc::channel(4);
        let clients = Arc::new(Mutex::new(vec![
            ClientSession::new(slow_id, slow_tx, protocol::GAMEPLAY_VERSION),
            ClientSession::new(healthy_id, healthy_tx, protocol::GAMEPLAY_VERSION),
        ]));
        let session = GameSession::new();
        let map = session.state.map_info();
        let filler = ServerMessage::Error {
            code: "queued".into(),
            message: "queued".into(),
        };
        let first = send_unicasts(
            &clients,
            &HashMap::new(),
            &[(Recipient::Client(slow_id), filler)],
        )
        .await;
        assert_eq!(first.queue_high_water, 1);
        let delivery = send_unicasts(
            &clients,
            &HashMap::new(),
            &[
                (Recipient::Client(slow_id), map.clone()),
                (Recipient::Client(healthy_id), map),
            ],
        )
        .await;
        assert_eq!(delivery.queue_overflows, 1);
        let snapshot = ServerMessage::Snapshot(session.state.snapshot());
        let sent = broadcast_to_clients(&clients, &[snapshot]).await;
        assert_eq!(sent.queued_messages, 1);
        let clients = clients.lock().await;
        assert!(!clients[0].initialized);
        assert!(clients[0].is_closing());
        assert!(clients[1].initialized);
        assert!(matches!(
            slow_rx.try_recv().unwrap(),
            ServerMessage::Error { .. }
        ));
        assert!(slow_rx.try_recv().is_err());
        assert!(matches!(
            healthy_rx.try_recv().unwrap(),
            ServerMessage::MapInfo { .. }
        ));
        assert!(matches!(
            healthy_rx.try_recv().unwrap(),
            ServerMessage::Snapshot(_)
        ));
    }

    #[tokio::test]
    async fn active_slow_watcher_overflow_is_counted_once() {
        let slow_id = Uuid::new_v4();
        let healthy_id = Uuid::new_v4();
        let (slow_tx, _slow_rx) = tokio::sync::mpsc::channel(1);
        let (healthy_tx, mut healthy_rx) = tokio::sync::mpsc::channel(4);
        let clients = Arc::new(Mutex::new(vec![
            ClientSession::new(slow_id, slow_tx, protocol::GAMEPLAY_VERSION),
            ClientSession::new(healthy_id, healthy_tx, protocol::GAMEPLAY_VERSION),
        ]));
        let session = GameSession::new();
        let map = session.state.map_info();
        let initial = send_unicasts(
            &clients,
            &HashMap::new(),
            &[
                (Recipient::Client(slow_id), map.clone()),
                (Recipient::Client(healthy_id), map),
            ],
        )
        .await;
        assert_eq!(initial.queued_messages, 2);
        let snapshot = ServerMessage::Snapshot(session.state.snapshot());
        let first = broadcast_to_clients(&clients, std::slice::from_ref(&snapshot)).await;
        let second = broadcast_to_clients(&clients, &[snapshot]).await;
        assert_eq!(first.queue_overflows, 1);
        assert_eq!(first.queued_messages, 1);
        assert_eq!(second.queue_overflows, 0);
        assert_eq!(second.queued_messages, 1);
        assert!(clients.lock().await[0].is_closing());
        assert!(matches!(
            healthy_rx.try_recv().unwrap(),
            ServerMessage::MapInfo { .. }
        ));
        for _ in 0..2 {
            assert!(matches!(
                healthy_rx.try_recv().unwrap(),
                ServerMessage::Snapshot(_)
            ));
        }
    }

    #[test]
    fn join_agent_pushes_player_joined_event() {
        let mut session = GameSession::new();
        let client_id = Uuid::new_v4();
        let player_id = Uuid::new_v4();

        session.apply_command(GameCommand::Connected {
            id: client_id,
            role: Role::Agent,
            name: "ArenaFox".to_string(),
            player_id: Some(player_id),
        });

        assert_eq!(session.state.players.len(), 1);
        assert_eq!(session.client_to_player.get(&client_id), Some(&player_id));

        let events = session.state.take_events();
        assert!(
            events.iter().any(|e| matches!(
                e,
                protocol::GameEvent::PlayerJoined {
                    player,
                    role,
                    player_count: 1,
                    ..
                } if player == "ArenaFox" && role == "agent"
            )),
            "expected PlayerJoined, got {:?}",
            events
        );
    }

    #[test]
    fn join_spectator_does_not_add_player() {
        let mut session = GameSession::new();
        session.apply_command(GameCommand::Connected {
            id: Uuid::new_v4(),
            role: Role::Spectator,
            name: "Watcher".to_string(),
            player_id: None,
        });
        assert!(session.state.players.is_empty());
        assert!(session.state.take_events().is_empty());
    }

    #[test]
    fn leave_pushes_player_left_with_score_and_count() {
        let mut session = GameSession::new();
        let client_id = Uuid::new_v4();
        let player_id = Uuid::new_v4();

        session.apply_command(GameCommand::Connected {
            id: client_id,
            role: Role::Human,
            name: "Joiner".to_string(),
            player_id: Some(player_id),
        });
        let _ = session.state.take_events();
        *session.state.scores.get_mut(&player_id).unwrap() = 7;

        session.apply_command(GameCommand::Disconnected { id: client_id });

        assert!(session.state.players.is_empty());
        assert!(!session.client_to_player.contains_key(&client_id));

        let events = session.state.take_events();
        assert!(
            events.iter().any(|e| matches!(
                e,
                protocol::GameEvent::PlayerLeft {
                    player,
                    score: 7,
                    player_count: 0,
                    ..
                } if player == "Joiner"
            )),
            "expected PlayerLeft, got {:?}",
            events
        );
    }

    #[test]
    fn disconnect_unknown_client_is_noop() {
        let mut session = GameSession::new();
        session.apply_command(GameCommand::Disconnected { id: Uuid::new_v4() });
        assert!(session.state.take_events().is_empty());
    }

    #[test]
    fn action_command_sets_player_intent() {
        let mut session = GameSession::new();
        let client_id = Uuid::new_v4();
        let player_id = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: client_id,
            role: Role::Agent,
            name: "Shooter".to_string(),
            player_id: Some(player_id),
        });
        let _ = session.state.take_events();

        session.apply_command(GameCommand::Action {
            player_id,
            action: Action {
                forward: true,
                fire: true,
                ..Default::default()
            },
        });

        let player = session
            .state
            .players
            .iter()
            .find(|p| p.id == player_id)
            .expect("player present");
        assert!(player.pending_action.forward);
        assert!(player.pending_action.fire);
    }

    #[test]
    fn tick_messages_emit_snapshot_and_round_events() {
        let mut session = GameSession::new();
        session.spawn_bots(2);
        session.state.start_round();

        let msgs = session.tick_messages(0.05);
        assert!(
            msgs.iter().any(|m| matches!(m, ServerMessage::Snapshot(_))),
            "expected Snapshot"
        );
        // Round start was pushed by start_round; tick drains remaining events if any.
        assert!(!msgs.is_empty());
    }

    #[test]
    fn spawn_bots_adds_named_agents() {
        let mut session = GameSession::new();
        session.spawn_bots(4);
        assert_eq!(session.state.players.len(), 4);
        assert_eq!(session.bots.len(), 4);
        assert_eq!(session.min_bots, 4);
        let names: Vec<_> = session
            .state
            .players
            .iter()
            .map(|p| p.name.as_str())
            .collect();
        assert!(names.contains(&"Dead Air Dan"));
        assert!(names.contains(&"Nightfall"));
        assert!(names.contains(&"Static Kid"));
        assert!(names.contains(&"Aunt Linda"));
        assert!(session
            .state
            .roster_host_line
            .as_ref()
            .is_some_and(|h| h.contains("DEAD AIR DAN") && h.contains("ON THE SCRAP")));
    }

    #[test]
    fn spawn_bots_roster_is_contested_frequency_callsigns() {
        let roster: Vec<_> = GameSession::rule_bot_roster()
            .iter()
            .map(|(n, _)| *n)
            .collect();
        assert_eq!(roster.len(), 8);
        assert!(!roster
            .iter()
            .any(|n| n.starts_with("Bot") || *n == "Rusher"));
        assert!(roster.contains(&"Buzzkill"));
        assert!(roster.contains(&"Tin Foil Tina"));
    }

    #[test]
    fn warmup_snapshot_host_line_names_scrap_roster() {
        let mut session = GameSession::new();
        session.spawn_bots(4);
        assert_eq!(session.state.round_state, crate::sim::RoundState::Warmup);
        let snap = session.state.snapshot();
        assert!(
            snap.host_line.contains("ON THE SCRAP"),
            "Warmup mid-join should name dialed-in scrap bots: {}",
            snap.host_line
        );
        assert!(snap.host_line.contains("DEAD AIR DAN"));
        assert!(
            snap.host_line.contains("CONTESTED FREQUENCY"),
            "Warmup should sell Contested Frequency bumper: {}",
            snap.host_line
        );
        assert!(
            snap.host_line.contains("ARENA DUEL"),
            "Warmup Host line should name the map: {}",
            snap.host_line
        );
        assert!(
            snap.round_time_left.is_some_and(|s| s >= 1),
            "Warmup Snapshot should expose countdown secs"
        );
        // RoundStart should carry map + roster fight bumper.
        session.state.start_round();
        let start = session
            .state
            .events
            .iter()
            .find_map(|e| match e {
                protocol::GameEvent::RoundStart { host_line, .. } => Some(host_line.clone()),
                _ => None,
            })
            .expect("RoundStart");
        assert!(start.contains("ON THE SCRAP"));
        assert!(start.contains("FIGHT!"));
        assert!(start.contains("ARENA DUEL"));
    }

    #[test]
    fn ensure_min_bots_refills_empty_arena() {
        let mut session = GameSession::new();
        session.set_min_bots(4);
        assert_eq!(session.bots.len(), 4);
        assert_eq!(session.state.players.len(), 4);

        // Simulate emptied rule-bot roster (solo must not stay empty).
        session.bots.clear();
        session.state.bots.clear();
        session.state.players.clear();
        session.ensure_min_bots();
        assert_eq!(session.bots.len(), 4);
        assert_eq!(session.state.players.len(), 4);
    }

    #[test]
    fn ensure_min_bots_noop_when_stocked_or_zero() {
        let mut session = GameSession::new();
        session.ensure_min_bots();
        assert!(session.bots.is_empty());

        session.spawn_bots(2);
        let before = session.bots.len();
        session.ensure_min_bots();
        assert_eq!(session.bots.len(), before);

        session.set_min_bots(2);
        session.ensure_min_bots();
        assert_eq!(session.bots.len(), 2);
    }

    #[test]
    fn tick_messages_ensures_min_bots_before_ai() {
        let mut session = GameSession::new();
        session.min_bots = 3;
        assert!(session.bots.is_empty());
        let _ = session.tick_messages(0.05);
        assert_eq!(session.bots.len(), 3);
        assert!(session.state.players.len() >= 3);
    }

    #[test]
    fn join_then_leave_round_trip_updates_player_count_on_events() {
        let mut session = GameSession::new();
        session.spawn_bots(2);
        let c1 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        let c2 = Uuid::new_v4();
        let p2 = Uuid::new_v4();

        session.apply_command(GameCommand::Connected {
            id: c1,
            role: Role::Agent,
            name: "A".to_string(),
            player_id: Some(p1),
        });
        session.apply_command(GameCommand::Connected {
            id: c2,
            role: Role::Agent,
            name: "B".to_string(),
            player_id: Some(p2),
        });
        let events = session.state.take_events();
        let join_counts: Vec<_> = events
            .iter()
            .filter_map(|e| match e {
                protocol::GameEvent::PlayerJoined { player_count, .. } => Some(*player_count),
                _ => None,
            })
            .collect();
        assert_eq!(join_counts, vec![3, 4]);

        session.apply_command(GameCommand::Disconnected { id: c1 });
        let events = session.state.take_events();
        assert!(events.iter().any(|e| matches!(
            e,
            protocol::GameEvent::PlayerLeft {
                player_count: 3,
                ..
            }
        )));
    }

    #[test]
    fn speak_command_pushes_rate_limited_event() {
        let mut session = GameSession::new();
        let client_id = Uuid::new_v4();
        let player_id = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: client_id,
            role: Role::Agent,
            name: "ArenaFox".to_string(),
            player_id: Some(player_id),
        });
        let _ = session.state.take_events();

        session.apply_command(GameCommand::Speak {
            player_id,
            text: "  nice scrap  ".to_string(),
        });
        let events = session.state.take_events();
        assert!(
            events.iter().any(|e| matches!(
                e,
                protocol::GameEvent::Speak {
                    player,
                    text,
                    ..
                } if player == "ArenaFox" && text == "nice scrap"
            )),
            "expected Speak, got {:?}",
            events
        );

        // Rate limit: immediate second speak is dropped + Error unicast.
        session.apply_command(GameCommand::Speak {
            player_id,
            text: "again".to_string(),
        });
        assert!(
            session.state.take_events().is_empty(),
            "rate-limited speak must not emit"
        );
        // Joining also queues a MapInfo, so look for the rejection rather
        // than assuming it is the only unicast in the queue.
        let unicasts = session.take_unicasts();
        let errors: Vec<_> = unicasts
            .iter()
            .filter(|(_, m)| matches!(m, ServerMessage::Error { .. }))
            .collect();
        assert_eq!(errors.len(), 1, "expected one speak Error unicast");
        assert_eq!(errors[0].0, Recipient::Player(player_id));
        match &errors[0].1 {
            ServerMessage::Error { code, message } => {
                assert_eq!(code, "speak_rate_limited");
                assert!(message.contains("rate limited"), "{message}");
            }
            other => panic!("expected Error, got {:?}", other),
        }

        // Advance ticks past cooldown.
        for _ in 0..crate::sim::SPEAK_COOLDOWN_TICKS {
            session.state.tick(0.05);
            let _ = session.state.take_events();
        }
        session.apply_command(GameCommand::Speak {
            player_id,
            text: "again".to_string(),
        });
        assert!(
            session.state.take_events().iter().any(|e| matches!(
                e,
                protocol::GameEvent::Speak { text, .. } if text == "again"
            )),
            "speak after cooldown must emit"
        );
    }

    #[test]
    fn speak_rejects_empty_and_overlong() {
        let mut session = GameSession::new();
        let player_id = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: Uuid::new_v4(),
            role: Role::Agent,
            name: "Talker".to_string(),
            player_id: Some(player_id),
        });
        let _ = session.state.take_events();

        session.apply_command(GameCommand::Speak {
            player_id,
            text: "   ".to_string(),
        });
        assert!(session.state.take_events().is_empty());
        let u = session.take_unicasts();
        assert!(
            u.iter().any(|(pid, m)| matches!(
                m,
                ServerMessage::Error { code, .. } if *pid == Recipient::Player(player_id) && code == "speak_rejected"
            )),
            "empty speak must Error unicast, got {:?}",
            u
        );

        let long = "x".repeat(crate::sim::SPEAK_MAX_CHARS + 1);
        session.apply_command(GameCommand::Speak {
            player_id,
            text: long,
        });
        assert!(session.state.take_events().is_empty());
        let u = session.take_unicasts();
        assert!(
            matches!(
                &u[..],
                [(pid, ServerMessage::Error { code, .. })]
                    if *pid == Recipient::Player(player_id) && code == "speak_rejected"
            ),
            "overlong speak must Error unicast, got {:?}",
            u
        );
    }

    #[test]
    fn agent_set_display_behavior_echoes_in_snapshot() {
        let mut session = GameSession::new();
        let client = Uuid::new_v4();
        let player = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: client,
            role: Role::Agent,
            name: "Brain-1".into(),
            player_id: Some(player),
        });
        session.apply_command(GameCommand::SetDisplayBehavior {
            player_id: player,
            behavior: "push_enemy".into(),
        });
        let snap = session.state.snapshot();
        let me = snap
            .players
            .iter()
            .find(|p| p.id == player)
            .expect("agent in snapshot");
        assert_eq!(me.behavior.as_deref(), Some("push_enemy"));

        session.apply_command(GameCommand::SetDisplayBehavior {
            player_id: player,
            behavior: "hold_angle".into(),
        });
        let snap = session.state.snapshot();
        let me = snap.players.iter().find(|p| p.id == player).unwrap();
        assert_eq!(me.behavior.as_deref(), Some("hold_angle"));
    }

    #[test]
    fn human_and_rule_bot_cannot_set_display_behavior() {
        let mut session = GameSession::new();
        let human_client = Uuid::new_v4();
        let human = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: human_client,
            role: Role::Human,
            name: "Player".into(),
            player_id: Some(human),
        });
        assert!(!session.state.set_display_behavior(human, "push_enemy"));
        let snap = session.state.snapshot();
        let me = snap.players.iter().find(|p| p.id == human).unwrap();
        assert!(me.behavior.is_none());

        session.spawn_bots(1);
        let bot_id = session.state.bots[0].player_id;
        assert!(!session.state.set_display_behavior(bot_id, "push_enemy"));
        let snap = session.state.snapshot();
        let bot = snap.players.iter().find(|p| p.id == bot_id).unwrap();
        assert_eq!(bot.behavior.as_deref(), Some("Aggressive"));
    }

    #[test]
    fn compliance_drone_spawn_does_not_inflate_min_bots() {
        let mut session = GameSession::new();
        session.spawn_bots(2);
        assert_eq!(session.min_bots, 2);
        assert_eq!(session.bots.len(), 2);

        session.state.start_round();
        session.state.config.boss_spawn_ticks = Some(1);
        session.state.config.compliance_ping_ticks = None;
        // Advance Active to spawn tick.
        while !session.state.boss_spawned {
            let _ = session.tick_messages(0.05);
            if session.state.round_ticks > 20 {
                panic!("boss should have spawned");
            }
        }
        assert!(session.state.boss_id.is_some());
        assert_eq!(
            session.bots.len(),
            2,
            "rule-bot roster must stay at min_bots"
        );
        assert_eq!(session.min_bots, 2);
        // Boss is on state.bots for AI + behavior chip.
        assert!(session
            .state
            .bots
            .iter()
            .any(|b| b.behavior == crate::sim::BotBehavior::Compliance));
        // Snapshot must list the drone.
        let snap = session.state.snapshot();
        assert!(snap
            .players
            .iter()
            .any(|p| p.name == protocol::BOSS_NAME && p.behavior.as_deref() == Some("Compliance")));
        assert_eq!(snap.pressure.as_deref(), Some("compliance_drone"));
    }

    #[test]
    fn reconnect_same_name_after_leave_is_single_player() {
        let mut session = GameSession::new();
        let c1 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: c1,
            role: Role::Human,
            name: "Human Player".to_string(),
            player_id: Some(p1),
        });
        let _ = session.state.take_events();

        session.apply_command(GameCommand::Disconnected { id: c1 });
        assert!(session.state.players.is_empty());
        let _ = session.state.take_events();

        let c2 = Uuid::new_v4();
        let p2 = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: c2,
            role: Role::Human,
            name: "Human Player".to_string(),
            player_id: Some(p2),
        });

        assert_eq!(session.state.players.len(), 1);
        assert_eq!(session.state.players[0].id, p2);
        assert_eq!(session.state.players[0].name, "Human Player");
        assert_eq!(session.client_to_player.get(&c2), Some(&p2));
        assert!(!session.client_to_player.contains_key(&c1));
    }

    #[test]
    fn duplicate_callsigns_cannot_evict_another_connection() {
        let mut session = GameSession::new();
        let old_client = Uuid::new_v4();
        let old_player = Uuid::new_v4();
        let new_client = Uuid::new_v4();
        let new_player = Uuid::new_v4();
        for (client, player) in [(old_client, old_player), (new_client, new_player)] {
            session.apply_command(GameCommand::Connected {
                id: client,
                role: Role::Human,
                name: "Meat Proxy".into(),
                player_id: Some(player),
            });
        }
        assert_eq!(session.state.players.len(), 2);
        assert_eq!(session.client_to_player.get(&old_client), Some(&old_player));
        assert_eq!(session.client_to_player.get(&new_client), Some(&new_player));
        assert_eq!(
            session
                .state
                .players
                .iter()
                .find(|p| p.id == old_player)
                .unwrap()
                .name,
            "Meat Proxy"
        );
        assert_eq!(
            session
                .state
                .players
                .iter()
                .find(|p| p.id == new_player)
                .unwrap()
                .name,
            "Meat Proxy #2"
        );
        assert!(!session
            .state
            .take_events()
            .iter()
            .any(|event| matches!(event, protocol::GameEvent::PlayerLeft { .. })));
        session.apply_command(GameCommand::Disconnected { id: old_client });
        assert_eq!(session.state.players.len(), 1);
        assert_eq!(session.state.players[0].id, new_player);
        session.apply_command(GameCommand::Action {
            player_id: new_player,
            action: Action {
                fire: true,
                ..Default::default()
            },
        });
        assert!(session.state.players[0].pending_action.fire);
    }

    #[test]
    fn callsigns_are_bounded_and_cannot_spoof_roster_lines() {
        let mut session = GameSession::new();
        assert_eq!(session.available_display_name("  \n\t  "), "Player");
        assert_eq!(session.available_display_name("  Patch\n\t "), "Patch");
        assert_eq!(
            session
                .available_display_name(&"x".repeat(100))
                .chars()
                .count(),
            24
        );
        for expected in ["Patch", "Patch #2", "Patch #3"] {
            let name = session.available_display_name("Patch");
            assert_eq!(name, expected);
            session.state.add_player(Uuid::new_v4(), name, Role::Agent);
        }
    }
    #[test]
    fn reconnect_new_name_is_new_session_without_ghost() {
        let mut session = GameSession::new();
        let c1 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: c1,
            role: Role::Human,
            name: "Alpha".to_string(),
            player_id: Some(p1),
        });
        session.apply_command(GameCommand::Disconnected { id: c1 });
        let _ = session.state.take_events();

        let c2 = Uuid::new_v4();
        let p2 = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: c2,
            role: Role::Human,
            name: "Bravo".to_string(),
            player_id: Some(p2),
        });

        assert_eq!(session.state.players.len(), 1);
        assert_eq!(session.state.players[0].name, "Bravo");
        assert_eq!(session.client_to_player.len(), 1);
    }

    #[test]
    fn reconnect_same_name_does_not_evict_rule_bot() {
        let mut session = GameSession::new();
        session.spawn_bots(1);
        assert_eq!(session.state.players.len(), 1);
        let bot_name = session.state.players[0].name.clone();
        let bot_id = session.state.players[0].id;

        let c1 = Uuid::new_v4();
        let p1 = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            id: c1,
            role: Role::Human,
            name: bot_name.clone(),
            player_id: Some(p1),
        });

        assert_eq!(session.state.players.len(), 2);
        assert!(session.state.players.iter().any(|p| p.id == bot_id));
        assert!(session.state.players.iter().any(|p| p.id == p1));
    }
}
