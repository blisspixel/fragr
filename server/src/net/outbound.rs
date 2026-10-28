//! Bounded ordered delivery with one replaceable pending world. Resolved
//! combat and discrete state changes remain in their original FIFO positions.
//!
//! A broadcast is encoded once on the tick and every recipient's queue holds
//! the same immutable payload. A targeted message stays a typed value that
//! its own writer encodes, so private state never enters a shared payload.

use crate::bench::{Histogram, Summary};
use crate::protocol::delta::{EncodedWorld, WorldEncoder};
use crate::protocol::{PlayerState, ServerMessage, Snapshot};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::mpsc::error::TryRecvError;
use tokio::sync::Notify;

/// Who may receive a broadcast. The class follows from the message itself,
/// so no caller can label a booth fact for players by mistake.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Audience {
    /// Every initialized session.
    Everyone,
    /// Only sessions that watch and hold no fighter: the booth.
    Spectators,
}

impl Audience {
    pub fn of(message: &ServerMessage) -> Self {
        match message {
            ServerMessage::SpectatorFacts(_) => Self::Spectators,
            _ => Self::Everyone,
        }
    }
}

/// One message every session of its audience receives unchanged, with the
/// exact JSON text each of their writers sends. Immutable once built.
#[derive(Debug)]
pub struct Broadcast {
    message: ServerMessage,
    text: String,
    audience: Audience,
    /// For a world, its tick and the delta from the tick's previous world.
    world: Option<EncodedWorld>,
}

impl Broadcast {
    /// One broadcast with no delta: every reader gets the full text.
    pub fn encode(message: ServerMessage) -> serde_json::Result<Arc<Self>> {
        Self::encode_with(message, None)
    }

    fn encode_with(
        message: ServerMessage,
        encoder: Option<&mut WorldEncoder>,
    ) -> serde_json::Result<Arc<Self>> {
        let text = serde_json::to_string(&message)?;
        let audience = Audience::of(&message);
        let world = match encoder {
            Some(encoder) => encoder.observe(&message, &text),
            None => match &message {
                ServerMessage::Snapshot(snapshot) => Some(EncodedWorld {
                    tick: snapshot.tick,
                    delta: None,
                }),
                _ => None,
            },
        };
        Ok(Arc::new(Self {
            message,
            text,
            audience,
            world,
        }))
    }

    pub fn audience(&self) -> Audience {
        self.audience
    }

    /// Encode a tick's broadcasts in order. One failure fails the tick.
    pub fn encode_all(
        messages: impl IntoIterator<Item = ServerMessage>,
    ) -> serde_json::Result<Vec<Arc<Self>>> {
        messages.into_iter().map(Self::encode).collect()
    }

    /// Encode a tick's broadcasts in order, each world also as a delta from
    /// the world `encoder` saw last.
    pub fn encode_tick(
        messages: impl IntoIterator<Item = ServerMessage>,
        encoder: &mut WorldEncoder,
    ) -> serde_json::Result<Vec<Arc<Self>>> {
        messages
            .into_iter()
            .map(|message| Self::encode_with(message, Some(&mut *encoder)))
            .collect()
    }

    /// The world this broadcast carries, if it is one.
    pub fn world(&self) -> Option<&EncodedWorld> {
        self.world.as_ref()
    }

    /// Copies of borrowed test messages, encoded as a tick would.
    #[cfg(test)]
    pub(crate) fn copies(messages: &[ServerMessage]) -> Vec<Arc<Self>> {
        Self::encode_all(messages.iter().cloned()).expect("test broadcasts encode")
    }

    pub fn message(&self) -> &ServerMessage {
        &self.message
    }

    /// The bytes on the wire for every recipient.
    pub fn text(&self) -> &str {
        &self.text
    }
}

/// What a session queue holds: a shared broadcast or one targeted message.
/// A message is several kilobytes inline, so a targeted one is boxed and a
/// queue slot stays pointer sized.
#[derive(Debug)]
pub enum Outbound {
    Shared(Arc<Broadcast>),
    Targeted(Box<ServerMessage>),
}

impl Outbound {
    pub fn message(&self) -> &ServerMessage {
        match self {
            Self::Shared(broadcast) => broadcast.message(),
            Self::Targeted(message) => message,
        }
    }

    /// The typed message, copied out of a shared broadcast.
    pub fn into_message(self) -> ServerMessage {
        match self {
            Self::Shared(broadcast) => broadcast.message().clone(),
            Self::Targeted(message) => *message,
        }
    }
}

impl From<ServerMessage> for Outbound {
    fn from(message: ServerMessage) -> Self {
        Self::Targeted(Box::new(message))
    }
}

impl From<Arc<Broadcast>> for Outbound {
    fn from(broadcast: Arc<Broadcast>) -> Self {
        Self::Shared(broadcast)
    }
}

/// One message as the socket writer takes it, with the moment it was queued.
#[derive(Debug)]
pub struct Delivery {
    pub frame: Outbound,
    pub queued_at: Instant,
}

struct State {
    queue: VecDeque<Delivery>,
    pending_world: Option<usize>,
    capacity: usize,
    senders: usize,
    closed: bool,
}

struct Shared {
    state: Mutex<State>,
    ready: Notify,
}

pub struct WsTx(Arc<Shared>);
pub struct WsRx(Arc<Shared>);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Queued {
    Added,
    ReplacedWorld,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QueueError {
    Full,
    Closed,
}

pub fn channel(capacity: usize) -> (WsTx, WsRx) {
    assert!(capacity > 0, "outbound capacity must be positive");
    let shared = Arc::new(Shared {
        state: Mutex::new(State {
            queue: VecDeque::with_capacity(capacity),
            pending_world: None,
            capacity,
            senders: 1,
            closed: false,
        }),
        ready: Notify::new(),
    });
    (WsTx(Arc::clone(&shared)), WsRx(shared))
}

impl Clone for WsTx {
    fn clone(&self) -> Self {
        self.0
            .state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .senders += 1;
        Self(Arc::clone(&self.0))
    }
}

impl Drop for WsTx {
    fn drop(&mut self) {
        let mut state = self.0.state.lock().unwrap_or_else(|e| e.into_inner());
        state.senders -= 1;
        if state.senders == 0 {
            self.0.ready.notify_one();
        }
    }
}

impl WsTx {
    pub fn try_send(&self, frame: impl Into<Outbound>) -> Result<Queued, QueueError> {
        let frame = frame.into();
        let mut state = self.0.state.lock().unwrap_or_else(|e| e.into_inner());
        if state.closed {
            return Err(QueueError::Closed);
        }
        let message = frame.message();
        let replace = match (message, state.pending_world) {
            (ServerMessage::Snapshot(new), Some(index)) => match state.queue[index].frame.message()
            {
                ServerMessage::Snapshot(old) => can_replace(old, new),
                _ => unreachable!("pending world must index a snapshot"),
            },
            _ => false,
        };
        if !replace && state.queue.len() == state.capacity {
            return Err(QueueError::Full);
        }
        if replace {
            let index = state.pending_world.take().expect("replacement has a world");
            state.queue.remove(index);
        }
        if matches!(message, ServerMessage::Snapshot(_)) {
            // A predecessor that cannot be replaced becomes a reliable fact
            // carrier. Moving the latest world to the tail preserves geometry,
            // events and acknowledgements that arrived in between.
            state.pending_world = Some(state.queue.len());
        } else if matches!(
            message,
            ServerMessage::MapInfo { .. } | ServerMessage::Mission { .. }
        ) {
            // Never compare or replace a world across a geometry/mission
            // boundary, even when both worlds reuse the same map id.
            state.pending_world = None;
        }
        state.queue.push_back(Delivery {
            frame,
            queued_at: Instant::now(),
        });
        drop(state);
        self.0.ready.notify_one();
        Ok(if replace {
            Queued::ReplacedWorld
        } else {
            Queued::Added
        })
    }

    pub fn depth(&self) -> usize {
        self.0
            .state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .queue
            .len()
    }
}

impl WsRx {
    pub fn try_take(&mut self) -> Result<Delivery, TryRecvError> {
        let mut state = self.0.state.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(delivery) = state.queue.pop_front() {
            state.pending_world = state.pending_world.and_then(|index| index.checked_sub(1));
            Ok(delivery)
        } else if state.senders == 0 {
            Err(TryRecvError::Disconnected)
        } else {
            Err(TryRecvError::Empty)
        }
    }

    /// The queued message alone, for code that inspects rather than sends.
    pub fn try_recv(&mut self) -> Result<ServerMessage, TryRecvError> {
        self.try_take()
            .map(|delivery| delivery.frame.into_message())
    }

    pub async fn recv(&mut self) -> Option<Delivery> {
        loop {
            // There is only one consumer. A send after try_take stores a Notify
            // permit, so neither this wait nor cancelling it can lose a wakeup.
            match self.try_take() {
                Ok(delivery) => return Some(delivery),
                Err(TryRecvError::Disconnected) => return None,
                Err(TryRecvError::Empty) => self.0.ready.notified().await,
            }
        }
    }
}

/// Writer-side measurements for the local fan-out harness. A production
/// listener has no probe, so its writers never lock this.
#[derive(Debug, Default)]
pub struct WriterProbe(Mutex<WriterSamples>);

#[derive(Debug, Default)]
struct WriterSamples {
    residence_ns: Histogram,
    encode_ns: Histogram,
    send_ns: Histogram,
    encodes: u64,
    encoded_bytes: u64,
    shared_frames: u64,
    shared_bytes: u64,
    delta_frames: u64,
    delta_bytes: u64,
    /// When the measured window began: the last reset.
    since: Option<Instant>,
    /// Writers that gave up on a send (timeout or socket error), by when.
    send_failures: Vec<Duration>,
    /// Of those, writers whose oldest unsent frame went stale.
    stale_closes: u64,
    /// Of those, writers whose reader fell behind the stream.
    behind_closes: u64,
}

/// What every session writer did with its text frames.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct WriterReport {
    /// Enqueue to the writer taking the message off its queue.
    pub residence_ms: Summary,
    /// JSON serialization inside a writer, one sample per encode.
    pub encode_ms: Summary,
    /// Framing and the socket write: send completion, not peer receipt.
    pub send_ms: Summary,
    /// Messages a writer serialized itself.
    pub encodes: u64,
    pub encoded_bytes: u64,
    /// Frames sent from a payload the tick encoded once for every recipient.
    pub shared_frames: u64,
    /// Bytes copied from shared payloads into per-socket frames.
    pub shared_bytes: u64,
    /// Of the shared frames, worlds sent as a delta, and their bytes.
    pub delta_frames: u64,
    pub delta_bytes: u64,
    /// Milliseconds into the window at which a writer's send timed out or
    /// failed, closing that connection, stale closes included.
    pub send_failures_ms: Vec<f64>,
    /// Writers closed because their oldest unsent frame went stale.
    pub stale_closes: u64,
    /// Writers closed because their reader left a ping unanswered too long.
    pub behind_closes: u64,
}

fn nanos(duration: Duration) -> u64 {
    u64::try_from(duration.as_nanos()).unwrap_or(u64::MAX)
}

impl WriterProbe {
    fn samples(&self) -> std::sync::MutexGuard<'_, WriterSamples> {
        self.0.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub(crate) fn taken(&self, queued_at: Instant, now: Instant) {
        self.samples()
            .residence_ns
            .record(nanos(now.saturating_duration_since(queued_at)));
    }

    pub(crate) fn encoded(&self, elapsed: Duration, bytes: usize) {
        let mut samples = self.samples();
        samples.encode_ns.record(nanos(elapsed));
        samples.encodes += 1;
        samples.encoded_bytes += bytes as u64;
    }

    pub(crate) fn shared(&self, bytes: usize, delta: bool) {
        let mut samples = self.samples();
        samples.shared_frames += 1;
        samples.shared_bytes += bytes as u64;
        if delta {
            samples.delta_frames += 1;
            samples.delta_bytes += bytes as u64;
        }
    }

    pub(crate) fn sent(&self, elapsed: Duration) {
        self.samples().send_ns.record(nanos(elapsed));
    }

    /// A writer stopped because a send timed out or failed.
    pub(crate) fn send_failed(&self, at: Instant) {
        let mut samples = self.samples();
        let since = samples.since.unwrap_or(at);
        samples
            .send_failures
            .push(at.saturating_duration_since(since));
    }

    /// A writer closed its socket because a queued frame went stale.
    pub(crate) fn went_stale(&self, at: Instant) {
        self.send_failed(at);
        self.samples().stale_closes += 1;
    }

    /// A writer closed its socket because its reader left a ping unanswered.
    pub(crate) fn fell_behind(&self, at: Instant) {
        self.send_failed(at);
        self.samples().behind_closes += 1;
    }

    pub fn reset(&self) {
        *self.samples() = WriterSamples {
            since: Some(Instant::now()),
            ..WriterSamples::default()
        };
    }

    pub fn report(&self) -> WriterReport {
        let samples = self.samples();
        WriterReport {
            residence_ms: samples.residence_ns.summary(1e-6),
            encode_ms: samples.encode_ns.summary(1e-6),
            send_ms: samples.send_ns.summary(1e-6),
            encodes: samples.encodes,
            encoded_bytes: samples.encoded_bytes,
            shared_frames: samples.shared_frames,
            shared_bytes: samples.shared_bytes,
            delta_frames: samples.delta_frames,
            delta_bytes: samples.delta_bytes,
            send_failures_ms: samples
                .send_failures
                .iter()
                .map(|at| at.as_secs_f64() * 1000.0)
                .collect(),
            stale_closes: samples.stale_closes,
            behind_closes: samples.behind_closes,
        }
    }
}

impl Drop for WsRx {
    fn drop(&mut self) {
        let mut state = self.0.state.lock().unwrap_or_else(|e| e.into_inner());
        state.closed = true;
        state.queue.clear();
        state.pending_world = None;
    }
}

/// Deliberately enumerate the entire snapshot: adding a field requires deciding
/// whether it is replaceable motion or an exact fact. No serialization on the
/// enqueue path. Transient combat is retained even if a later shot looks equal.
fn can_replace(old: &Snapshot, new: &Snapshot) -> bool {
    let Snapshot {
        walker,
        vehicles,
        tick,
        players,
        round_state,
        round_time_left: _,
        sudden_death,
        frag_limit,
        shot_results,
        projectiles,
        grenades,
        assessor_canisters,
        rockets,
        mines,
        remote_mines,
        auditors,
        paver_strips,
        jetpacks,
        surveyor_marks,
        explosions,
        mode_name,
        playlist,
        pressure,
        host_line,
        mvp,
        mvp_frags,
        pickups,
        map_id,
        map_name,
        episode_id,
        episode_title,
        episode_objective,
        episode_progress,
        episode_phase,
        jammer_dish,
        team_scores,
        flags,
        capture_scores,
        capture_limit,
        sabotage,
        conquest,
        article_blade,
        podium,
        duel_queue,
    } = old;
    article_blade == &new.article_blade
        && podium == &new.podium
        && duel_queue == &new.duel_queue
        && walker == &new.walker
        && vehicles.len() == new.vehicles.len()
        && vehicles
            .iter()
            .zip(&new.vehicles)
            .all(|(a, b)| same_vehicle_facts(a, b))
        && *tick < new.tick
        && shot_results.is_empty()
        && explosions.is_empty()
        && players.len() == new.players.len()
        && players
            .iter()
            .zip(&new.players)
            .all(|(a, b)| same_player_facts(a, b))
        && round_state == &new.round_state
        && sudden_death == &new.sudden_death
        && frag_limit == &new.frag_limit
        && projectiles == &new.projectiles
        && grenades == &new.grenades
        && assessor_canisters == &new.assessor_canisters
        && rockets == &new.rockets
        && mines == &new.mines
        && remote_mines == &new.remote_mines
        && auditors == &new.auditors
        // A strip is an exact attack fact. Worn fuel is replaceable motion:
        // the same wearers in order may be superseded by a newer reading.
        && paver_strips == &new.paver_strips
        && jetpacks.len() == new.jetpacks.len()
        && jetpacks
            .iter()
            .zip(&new.jetpacks)
            .all(|(a, b)| a.player_id == b.player_id)
        // A disc's centre is motion; its owner, lifetime and tracking are facts.
        && surveyor_marks.len() == new.surveyor_marks.len()
        && surveyor_marks
            .iter()
            .zip(&new.surveyor_marks)
            .all(|(a, b)| {
                a.id == b.id && a.since == b.since && a.until == b.until && a.tracking == b.tracking
            })
        && mode_name == &new.mode_name
        && playlist == &new.playlist
        && pressure == &new.pressure
        && host_line == &new.host_line
        && mvp == &new.mvp
        && mvp_frags == &new.mvp_frags
        // Availability and every supply fact are exact; the snapshot carries
        // no countdown that a newer world could supersede.
        && pickups == &new.pickups
        && map_id == &new.map_id
        && map_name == &new.map_name
        && episode_id == &new.episode_id
        && episode_title == &new.episode_title
        && episode_objective == &new.episode_objective
        && episode_progress == &new.episode_progress
        && episode_phase == &new.episode_phase
        && jammer_dish == &new.jammer_dish
        && team_scores == &new.team_scores
        && flags == &new.flags
        && capture_scores == &new.capture_scores
        && capture_limit == &new.capture_limit
        && same_sabotage_facts(sabotage.as_ref(), new.sabotage.as_ref())
        && conquest == &new.conquest
}

fn same_vehicle_facts(
    old: &crate::protocol::VehicleState,
    new: &crate::protocol::VehicleState,
) -> bool {
    let crate::protocol::VehicleState {
        id,
        kind,
        position: _,
        yaw: _,
        speed: _,
        vy: _,
        hp,
        driver,
        gunner,
        gun_heat: _,
        burning_ticks,
        control_ready_tick,
    } = old;
    id == &new.id
        && kind == &new.kind
        && hp == &new.hp
        && driver == &new.driver
        && gunner == &new.gunner
        && (*burning_ticks > 0) == (new.burning_ticks > 0)
        && control_ready_tick == &new.control_ready_tick
}

fn same_player_facts(old: &PlayerState, new: &PlayerState) -> bool {
    let PlayerState {
        collidable,
        campaign,
        id,
        name,
        x: _,
        y: _,
        z: _,
        yaw: _,
        pitch: _,
        hp,
        armor,
        just_fired,
        behavior,
        score,
        deaths,
        attacks,
        connects,
        heads,
        damage,
        weapon,
        team,
        lives,
        golden,
        ducking,
        body,
        // A newer ping reading supersedes an older one, like motion.
        ping: _,
    } = old;
    !just_fired
        && collidable == &new.collidable
        && campaign == &new.campaign
        && id == &new.id
        && name == &new.name
        && hp == &new.hp
        && armor == &new.armor
        && behavior == &new.behavior
        && score == &new.score
        && deaths == &new.deaths
        && attacks == &new.attacks
        && connects == &new.connects
        && heads == &new.heads
        && damage == &new.damage
        && weapon == &new.weapon
        && team == &new.team
        && lives == &new.lives
        && golden == &new.golden
        && ducking == &new.ducking
        && body == &new.body
}

fn same_sabotage_facts(
    old: Option<&crate::protocol::SabotageState>,
    new: Option<&crate::protocol::SabotageState>,
) -> bool {
    match (old, new) {
        (None, None) => true,
        (Some(old), Some(new)) => {
            let mut prior = old.clone();
            prior.clock_ticks = new.clock_ticks;
            if let (Some(a), Some(b)) = (&mut prior.charge, &new.charge) {
                a.position = b.position;
            }
            if let (Some(a), Some(b)) = (&mut prior.progress, &new.progress) {
                a.ticks = b.ticks;
            }
            prior == *new
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests;
