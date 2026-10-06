//! The play loop. One WebSocket to the server, a 20 Hz controller that always
//! has an action ready, and a slower decision cadence that asks the brain for
//! intent without ever blocking the controller. At most one decision is in
//! flight; a slow answer is simply late, not queued.

use crate::budget::Budget;
use crate::decision::{
    campaign_questions, constrain_plan_weapon, plan_from_answers, stance_questions,
    tactical_questions, Gate, Question, Q_WEAPON,
};
use crate::local_model;
use crate::plan::{
    campaign_enemy_engageable_with_solids, campaign_micro_action_with_solids,
    campaign_target_with_solids, fallback_plan, micro_action, target_visible, Plan, Source, Stance,
};
use crate::provider::{decide, decision_request, Provider, Transport};
use crate::telemetry::{observe, EnemyView, RecentHits, Telemetry};
use crate::timeline::Timeline;
use crate::Error;
use fragr_server::protocol::{
    Action, CampaignDifficulty, CampaignRunStatus, ClientMessage, GameEvent, MissionId,
    MissionPhase, MissionState, Role, ServerMessage, SetDisplayBehavior, Snapshot,
};
use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;
use tokio_tungstenite::{connect_async, tungstenite::Message};
use uuid::Uuid;

/// The controller cadence: one action per server tick.
pub const MICRO_INTERVAL: Duration = Duration::from_millis(50);
/// Decisions per second are clamped to this range.
pub const MIN_DECISION_HZ: f64 = 0.1;
pub const MAX_DECISION_HZ: f64 = 5.0;
/// Each retryable failure doubles the decision interval, up to this many times.
pub const MAX_BACKOFF_LEVEL: u32 = 4;
/// Consecutive unreadable answers before the brain is switched off for the run.
pub const MAX_CONSECUTIVE_MALFORMED: u32 = 3;
/// How long to wait for the server to accept the socket.
pub const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
/// How long one outbound message may take before the socket is given up on.
pub const SEND_TIMEOUT: Duration = Duration::from_secs(2);
/// How long to wait for an in-flight decision after the loop ends, so its
/// charge lands in the ledger before the summary is read.
pub const DRAIN_TIMEOUT: Duration = Duration::from_secs(5);
/// Bound the wait for the final participant record after a terminal mission.
pub const TERMINAL_RECORD_TIMEOUT: Duration = Duration::from_secs(2);

/// The decision interval after `level` consecutive retryable failures.
pub fn backoff_interval(base: Duration, level: u32) -> Duration {
    base * 2u32.pow(level.min(MAX_BACKOFF_LEVEL))
}

/// Failures worth slowing down for: transport trouble, timeouts, rate limits,
/// and server errors. TypeSafe says to back off rather than retry at once; the
/// bot never retries inside a cycle, it just asks less often until one lands.
pub fn is_retryable(err: &Error) -> bool {
    matches!(
        err,
        Error::Transport(_)
            | Error::Timeout(_)
            | Error::Api {
                status: 408 | 429 | 500..=599,
                ..
            }
    )
}

/// Failures that will not get better by asking again: a bad key, a wrong
/// model id, a rejected request shape. One of these switches the brain off
/// for the rest of the run instead of billing a phantom charge every cycle.
pub fn is_fatal(err: &Error) -> bool {
    matches!(
        err,
        Error::Api {
            status: 400 | 401 | 403 | 404 | 422,
            ..
        } | Error::MissingApiKey(_)
            | Error::InvalidArgument(_)
    )
}

/// Whether a paid decision is worth asking for right now. Dead fighters and
/// fighters outside an active round only need local rules.
pub fn brain_worth_asking(telemetry: &Telemetry) -> bool {
    telemetry.hp > 0 && telemetry.round_state == "active"
}

/// Send one text frame with a bound on how long the socket may stall.
async fn send_text<S>(sink: &mut S, text: String) -> bool
where
    S: futures_util::Sink<Message> + Unpin,
{
    matches!(
        tokio::time::timeout(SEND_TIMEOUT, sink.send(Message::Text(text))).await,
        Ok(Ok(()))
    )
}

#[derive(Debug, Clone)]
pub struct BotConfig {
    pub server_url: String,
    pub name: String,
    pub provider: Provider,
    pub model: String,
    /// Required for paid providers; ignored for `Provider::Local`.
    pub api_key: Option<String>,
    /// Checked base URL of a free local model (`ollama`, `openjev`).
    pub model_url: Option<String>,
    /// The whole-decision latency budget for a local model. A later answer is
    /// a timeout and local rules play that cycle. Paid calls use the
    /// transport's own timeout.
    pub decision_budget: Duration,
    pub decision_hz: f64,
    pub gate: Gate,
    /// Leave the match after this long; `None` plays until the socket closes.
    pub max_seconds: Option<u64>,
    /// Optional local diagnostic file for bounded campaign observations.
    pub timeline_path: Option<PathBuf>,
    /// The pawn's body, sent in Hello. Presentation only.
    pub body: fragr_server::protocol::BodyKind,
}

/// What one run did, printed as JSON when it ends.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct BotSummary {
    pub name: String,
    /// Server-assigned participant identity, absent if admission never completed.
    pub player_id: Option<Uuid>,
    pub provider: String,
    pub model: String,
    pub snapshots: u64,
    pub actions_sent: u64,
    pub decisions_remote: u64,
    pub decisions_low_confidence: u64,
    /// Successful replies from an earlier map, life, round or mission state.
    pub decisions_discarded: u64,
    pub decisions_failed: u64,
    pub decisions_local: u64,
    pub budget_refusals: u64,
    /// Decisions that ran past their latency budget (counted in `decisions_failed`).
    pub timeouts: u64,
    /// Asked decisions that ended on local rules: low confidence, failed, refused.
    pub fallbacks: u64,
    /// Times the decision interval was doubled after a retryable failure.
    pub backoffs: u64,
    /// Failures that switched the brain off for the rest of the run.
    pub fatal_failures: u64,
    /// Why the brain was switched off, if it was.
    pub brain_disabled: Option<String>,
    pub frags: u32,
    /// Kills counted by the authoritative participant record, including missions.
    pub kills: Option<u64>,
    pub deaths: u32,
    /// Most recent validated mission state received from the authoritative server.
    pub mission: Option<MissionReceipt>,
    /// Whether a terminal campaign receipt includes its matching final record.
    /// `None` means this run did not observe a terminal campaign outcome.
    pub terminal_record_complete: Option<bool>,
    pub run_usd: f64,
    pub total_usd: f64,
    pub last_plan: Option<Plan>,
    pub last_state: Option<String>,
    pub decision_latency: LatencyStats,
    /// Wall time from joining to leaving.
    pub elapsed_seconds: f64,
    /// Model answers (trusted or not) per second of play.
    pub decisions_per_second: f64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct MissionReceipt {
    pub id: MissionId,
    pub difficulty: CampaignDifficulty,
    pub phase: MissionPhase,
    pub status: Option<CampaignRunStatus>,
    pub attempt: u32,
    pub continues: Option<u8>,
}

impl From<&MissionState> for MissionReceipt {
    fn from(state: &MissionState) -> Self {
        Self {
            id: state.id,
            difficulty: state.rules.difficulty,
            phase: state.phase,
            status: state.run.map(|run| run.status),
            attempt: state.attempt,
            continues: state.run.map(|run| run.continues),
        }
    }
}

fn set_record_counts(summary: &mut BotSummary, total: &fragr_server::protocol::CombatCounts) {
    summary.kills = Some(total.kills());
    summary.deaths = total.deaths.min(u64::from(u32::MAX)) as u32;
}

fn terminal_mission(state: &MissionState) -> bool {
    state.run.is_some_and(|run| {
        matches!(
            run.status,
            CampaignRunStatus::Complete | CampaignRunStatus::Failed
        )
    })
}

fn terminal_record_matches(
    state: &MissionState,
    record: &fragr_server::protocol::PlayerRecord,
) -> bool {
    use fragr_server::protocol::{RecordScope, RecordStatus};
    let expected = match state.run.map(|run| run.status) {
        Some(CampaignRunStatus::Complete) => RecordStatus::Complete,
        Some(CampaignRunStatus::Failed) => RecordStatus::Failed,
        _ => return false,
    };
    record.tick >= state.changed_at
        && record.status == expected
        && matches!(
            &record.scope,
            RecordScope::Mission { mission, attempt, rules, run }
                if *mission == state.id
                    && *attempt == state.attempt
                    && *rules == state.rules
                    && *run == state.run
        )
}

async fn drain_terminal_record<S>(
    stream: &mut S,
    id: Option<Uuid>,
    state: &MissionState,
    record: &mut Option<fragr_server::protocol::PlayerRecord>,
    summary: &mut BotSummary,
) -> Result<bool, Error>
where
    S: futures_util::Stream<Item = Result<Message, tokio_tungstenite::tungstenite::Error>> + Unpin,
{
    if record
        .as_ref()
        .is_some_and(|current| terminal_record_matches(state, current))
    {
        return Ok(true);
    }
    let wait = async {
        while let Some(message) = stream.next().await {
            match message {
                Ok(Message::Text(text)) => {
                    let incoming: ServerMessage = serde_json::from_str(&text).map_err(|error| {
                        Error::Transport(format!("invalid server message: {error}"))
                    })?;
                    if let ServerMessage::Record(next) = incoming {
                        next.validate_for(id, record.as_ref()).map_err(|error| {
                            Error::Transport(format!("invalid participant record: {error}"))
                        })?;
                        set_record_counts(summary, &next.total);
                        let complete = terminal_record_matches(state, &next);
                        *record = Some(next);
                        if complete {
                            return Ok(true);
                        }
                    }
                }
                Ok(Message::Close(_)) | Err(_) => return Ok(false),
                Ok(_) => {}
            }
        }
        Ok(false)
    };
    tokio::time::timeout(TERMINAL_RECORD_TIMEOUT, wait)
        .await
        .unwrap_or(Ok(false))
}

fn decision_state(
    telemetry: &Telemetry,
    mission: Option<&MissionState>,
    loadout: Option<&fragr_server::protocol::LoadoutState>,
    enemy_visible: Option<bool>,
) -> Value {
    let mut state = telemetry.state_object();
    if let Some(mission) = mission {
        state["mission"] = serde_json::to_value(MissionReceipt::from(mission))
            .expect("mission receipt is serializable");
        if state["enemy"]["present"] == true {
            state["enemy"]["visible"] = serde_json::json!(enemy_visible.unwrap_or(false));
        }
        state["self"]
            .as_object_mut()
            .expect("telemetry self is an object")
            .remove("score");
        state
            .as_object_mut()
            .expect("telemetry state is an object")
            .remove("clock");
    }
    if let Some(equipment) = loadout {
        state["equipment"] = serde_json::json!({
            "selected": equipment.selected, "weapons": equipment.weapons,
            "ammo": equipment.ammo,
            "grenades": equipment.grenades,
        });
    }
    state
}

enum Outcome {
    Decided(Plan),
    Refused(Error, Plan),
    Failed(Error, Plan),
}

/// One decision on its way back: the answer channel and the task behind it.
type InFlight = (oneshot::Receiver<(Outcome, u64)>, JoinHandle<()>, u64);

/// The local lifecycle changes independently of a blocking provider request.
/// Replies still settle their paid accounting, but cannot cross this boundary.
#[derive(Default)]
struct DecisionEpoch(u64);

impl DecisionEpoch {
    fn advance(&mut self) {
        self.0 = self.0.wrapping_add(1);
    }

    fn accepts(&self, requested: u64) -> bool {
        self.0 == requested
    }

    fn mission_changed(old: Option<&MissionState>, next: &MissionState) -> bool {
        fn intent_state(state: &MissionState) -> MissionState {
            let mut state = state.clone();
            state.changed_at = 0;
            state.prompts.clear();
            for member in &mut state.party {
                member.name.clear();
                member.aboard = false;
            }
            state.party.sort_unstable_by_key(|member| member.id);
            if let Some(facts) = &mut state.m02 {
                if let Some(evacuation) = &mut facts.evacuation {
                    evacuation.captives = [[0.0; 3]; 2];
                }
            }
            if let Some(facts) = &mut state.m03 {
                facts.mast_hp = i32::from(facts.mast_hp > 0);
                for car in &mut facts.cars {
                    car.captives = [[0.0; 3]; 2];
                }
            }
            if let Some(facts) = &mut state.m04 {
                for patient in &mut facts.patients {
                    patient.feet = [0.0; 3];
                }
            }
            if let Some(facts) = &mut state.m05 {
                for captive in &mut facts.captives {
                    captive.feet = [0.0; 3];
                }
                facts.tram.feet = [0.0; 3];
                facts.tram.tick = 0;
                // Temporary physical obstruction does not obsolete intent.
                if facts.tram.phase == fragr_server::protocol::M05TramPhase::Blocked {
                    facts.tram.phase = fragr_server::protocol::M05TramPhase::Moving;
                }
            }
            state
        }
        old.is_none_or(|old| intent_state(old) != intent_state(next))
    }

    fn observe_snapshot(&mut self, id: Option<Uuid>, old: Option<&Snapshot>, next: &Snapshot) {
        if let Some(old) = old {
            let living = |snapshot: &Snapshot| {
                snapshot
                    .players
                    .iter()
                    .find(|p| Some(p.id) == id)
                    .map(|p| p.hp > 0)
            };
            let flag_ownership = |snapshot: &Snapshot| {
                snapshot
                    .flags
                    .as_ref()
                    .map(|flags| flags.each_ref().map(|flag| (flag.status, flag.carrier)))
            };
            let cooperating = |snapshot: &Snapshot| {
                let mut peers: Vec<_> = snapshot
                    .players
                    .iter()
                    .filter(|p| {
                        Some(p.id) == id || p.behavior.as_deref().and_then(Stance::parse).is_some()
                    })
                    .map(|p| (p.id, p.team, p.hp > 0))
                    .collect();
                peers.sort_unstable_by_key(|peer| peer.0);
                peers
            };
            if old.map_id != next.map_id
                || old.round_state != next.round_state
                || living(old) != living(next)
                || flag_ownership(old) != flag_ownership(next)
                || cooperating(old) != cooperating(next)
            {
                self.advance();
            }
        }
    }
}

/// Round-trip time of sent decisions, in milliseconds.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct LatencyStats {
    pub samples: u64,
    pub min_ms: u64,
    pub max_ms: u64,
    pub mean_ms: f64,
    /// Nearest-rank percentiles over the retained samples, set by `finish`.
    pub p50_ms: u64,
    pub p95_ms: u64,
    #[serde(skip)]
    retained: Vec<u64>,
}

/// Samples kept for percentiles; hours of play at five decisions a second.
pub const LATENCY_SAMPLES_KEPT: usize = 100_000;

/// The nearest-rank percentile of sorted values, zero when empty.
pub fn percentile(sorted: &[u64], pct: f64) -> u64 {
    if sorted.is_empty() {
        return 0;
    }
    let rank = ((pct / 100.0) * sorted.len() as f64).ceil() as usize;
    sorted[rank.clamp(1, sorted.len()) - 1]
}

impl LatencyStats {
    /// Compute the percentiles from the samples seen so far.
    pub fn finish(&mut self) {
        let mut sorted = self.retained.clone();
        sorted.sort_unstable();
        self.p50_ms = percentile(&sorted, 50.0);
        self.p95_ms = percentile(&sorted, 95.0);
    }

    pub fn push(&mut self, ms: u64) {
        if self.retained.len() < LATENCY_SAMPLES_KEPT {
            self.retained.push(ms);
        }
        if self.samples == 0 {
            self.min_ms = ms;
            self.max_ms = ms;
        } else {
            self.min_ms = self.min_ms.min(ms);
            self.max_ms = self.max_ms.max(ms);
        }
        let total = self.mean_ms * self.samples as f64 + ms as f64;
        self.samples += 1;
        self.mean_ms = total / self.samples as f64;
    }
}

fn transport_err<E: std::fmt::Display>(err: E) -> Error {
    Error::Transport(err.to_string())
}

/// Wire JSON for SetDisplayBehavior when stance changes (including first publish).
fn display_behavior_wire(published: &mut Option<Stance>, stance: Stance) -> Option<String> {
    if published.as_ref() == Some(&stance) {
        return None;
    }
    *published = Some(stance);
    serde_json::to_string(&ClientMessage::SetDisplayBehavior(SetDisplayBehavior {
        behavior: stance.name().to_string(),
    }))
    .ok()
}

fn lock(budget: &Mutex<Budget>) -> std::sync::MutexGuard<'_, Budget> {
    budget
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// One draw in [0, 1) from a fighter's own stream. xorshift64star, in the repo
/// rather than from a crate, for the same reason the simulation's stream is:
/// the value sequence must not drift when a dependency updates.
/// A non-zero seed from a fighter's name. xorshift is stuck at zero forever, so
/// an empty name must not produce one.
/// The word for a plan that goes into the fighter's memory.
pub fn plan_word(plan: &Plan) -> &'static str {
    plan.stance.name()
}

/// Append a decision, collapsing a run of the same one into a single entry so
/// holding a stance for a while does not push an oscillation out of view.
pub fn remember(memory: &mut std::collections::VecDeque<String>, decision: &str) {
    if memory.back().map(String::as_str) == Some(decision) {
        return;
    }
    memory.push_back(decision.to_string());
    while memory.len() > crate::telemetry::RECENT_DECISIONS {
        memory.pop_front();
    }
}

pub fn seed_from_name(name: &str) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in name.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash | 1
}

pub fn next_roll(state: &mut u64) -> f64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    let value = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
    // Top 53 bits: every f64 in [0, 1) that has an exact representation.
    (value >> 11) as f64 / (1u64 << 53) as f64
}

/// Who answers a decision and how to reach them.
#[derive(Debug, Clone)]
struct Asker {
    provider: Provider,
    model: String,
    api_key: String,
    model_url: String,
    decision_budget: Duration,
}

impl Asker {
    fn from_config(config: &BotConfig) -> Self {
        Asker {
            provider: config.provider,
            model: config.model.clone(),
            api_key: config.api_key.clone().unwrap_or_default(),
            model_url: config.model_url.clone().unwrap_or_default(),
            decision_budget: config.decision_budget,
        }
    }

    /// The answers to one decision: free and unbudgeted for a local model,
    /// through the spend gate for a paid one.
    fn answers(
        &self,
        transport: &dyn Transport,
        budget: &Mutex<Budget>,
        state: &Value,
        questions: &BTreeMap<String, Question>,
    ) -> Result<BTreeMap<String, crate::decision::Answer>, Error> {
        if self.provider.is_local_model() {
            return local_model::decide(
                transport,
                self.provider,
                &self.model_url,
                &self.model,
                state,
                questions,
                self.decision_budget,
            )
            .map(|response| response.answers);
        }
        decision_request(self.provider, &self.model, &self.api_key, state, questions)
            .and_then(|request| decide(transport, budget, self.provider, &self.model, &request))
            .map(|decision| decision.response.answers)
    }
}

#[allow(clippy::too_many_arguments)]
fn spawn_decision(
    transport: Arc<dyn Transport>,
    budget: Arc<Mutex<Budget>>,
    questions: Arc<BTreeMap<String, Question>>,
    asker: Asker,
    state: Value,
    fallback: Plan,
    gate: Gate,
    // Where in the model's distribution this decision lands, in [0, 1), from
    // the fighter's own seeded stream so a run reproduces.
    roll: f64,
    tx: oneshot::Sender<(Outcome, u64)>,
) -> JoinHandle<()> {
    tokio::task::spawn_blocking(move || {
        let started = std::time::Instant::now();
        let result = asker
            .answers(transport.as_ref(), &budget, &state, &questions)
            .map(|answers| {
                let mut plan = plan_from_answers(&answers, &gate, &fallback, roll);
                if questions.contains_key(Q_WEAPON) {
                    constrain_plan_weapon(&mut plan, &questions);
                }
                plan
            });
        let outcome = match result {
            Ok(plan) => Outcome::Decided(plan),
            Err(err @ Error::Budget(_)) => Outcome::Refused(
                err,
                Plan {
                    source: Source::Budget,
                    ..fallback
                },
            ),
            Err(err) => Outcome::Failed(err, fallback),
        };
        let _ = tx.send((outcome, started.elapsed().as_millis() as u64));
    })
}

fn constrain_campaign_equipment(
    plan: &mut Plan,
    mission: bool,
    loadout: Option<&fragr_server::protocol::LoadoutState>,
) {
    if mission {
        plan.weapon = plan
            .weapon
            .filter(|weapon| loadout.is_some_and(|equipment| equipment.owns(*weapon)));
    }
}

fn align_campaign_enemy(
    telemetry: &mut Telemetry,
    id: Uuid,
    snapshot: &Snapshot,
    world: &fragr_server::navigation::Navigation,
    solids: Option<&[fragr_server::movement::Solid]>,
) {
    let mine = snapshot.players.iter().find(|player| player.id == id);
    telemetry.enemy = mine.and_then(|mine| {
        campaign_target_with_solids(id, snapshot, world, solids).map(|other| EnemyView {
            id: other.id,
            name: other.name.clone(),
            dist: (other.x - mine.x).hypot(other.z - mine.z),
            hp: other.hp,
            weapon: other.weapon.to_ascii_lowercase(),
        })
    });
}

/// Join the server as an agent and play until the socket closes, `stop` is
/// set, or `max_seconds` passes. Never returns early on brain trouble.
pub async fn run_bot(
    config: BotConfig,
    transport: Arc<dyn Transport>,
    budget: Arc<Mutex<Budget>>,
    stop: Arc<AtomicBool>,
) -> Result<BotSummary, Error> {
    if config.provider.is_paid() && config.api_key.as_deref().unwrap_or("").trim().is_empty() {
        return Err(Error::MissingApiKey(config.provider.key_names().join(", ")));
    }
    if config.provider.is_local_model()
        && (config.model_url.as_deref().unwrap_or("").is_empty()
            || config.decision_budget.is_zero())
    {
        return Err(Error::InvalidArgument(format!(
            "{} needs a checked model url and a latency budget",
            config.provider.name()
        )));
    }
    let started = std::time::Instant::now();
    let (ws, _) = tokio::time::timeout(CONNECT_TIMEOUT, connect_async(&config.server_url))
        .await
        .map_err(|_| Error::Transport(format!("connect to {} timed out", config.server_url)))?
        .map_err(transport_err)?;
    let (mut sink, mut stream) = ws.split();
    let hello = ClientMessage::Hello {
        body: Some(config.body),
        gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
        geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
        role: Role::Agent,
        name: config.name.clone(),
        ticket: fragr_server::join_ticket::ticket_for(Role::Agent),
        resume: None,
    };
    if !send_text(
        &mut sink,
        serde_json::to_string(&hello).map_err(transport_err)?,
    )
    .await
    {
        return Err(Error::Transport(
            "hello was not accepted in time".to_string(),
        ));
    }

    let mut published_stance: Option<Stance> = None;
    // This fighter's own stream, seeded off its name so two fighters in one
    // match do not draw the same sequence and move in lockstep.
    let mut roll_state: u64 = seed_from_name(&config.name);
    // What it last decided, which travels with the next state because the
    // model is stateless and cannot otherwise see its own oscillation.
    let mut memory: std::collections::VecDeque<String> = std::collections::VecDeque::new();
    let mut plan = Plan::default();
    if let Some(wire) = display_behavior_wire(&mut published_stance, plan.stance) {
        if !send_text(&mut sink, wire).await {
            return Err(Error::Transport(
                "first stance was not accepted in time".to_string(),
            ));
        }
    }

    let mut summary = BotSummary {
        name: config.name.clone(),
        provider: config.provider.name().to_string(),
        model: config.model.clone(),
        ..BotSummary::default()
    };
    let mut me: Option<Uuid> = None;
    let mut my_name = config.name.clone();
    let mut last: Option<Snapshot> = None;
    let mut loadout: Option<fragr_server::protocol::LoadoutState> = None;
    let mut record: Option<fragr_server::protocol::PlayerRecord> = None;
    let mut navigation = None;
    let mut navigator = fragr_server::navigation::Navigator::default();
    let mut stall = crate::plan::StallWatch::default();
    let mut mission_client = fragr_server::mission::MissionClient::default();
    let mut mission_geometry = None;
    let mut timeline = config.timeline_path.as_ref().map(|_| Timeline::default());
    let mut hits = RecentHits::default();
    // Whether a model is still being asked. A paid cap refusal, a fatal error,
    // or repeated unreadable answers switch it off for the rest of the run.
    let mut paid_enabled = config.provider.asks_a_model();
    let arena_questions = Arc::new(tactical_questions());
    let hz = if config.decision_hz.is_finite() {
        config.decision_hz.clamp(MIN_DECISION_HZ, MAX_DECISION_HZ)
    } else {
        3.0
    };
    let mut micro = tokio::time::interval(MICRO_INTERVAL);
    micro.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let base_interval = Duration::from_secs_f64(1.0 / hz);
    let mut backoff_level = 0u32;
    let mut macro_tick = tokio::time::interval(base_interval);
    macro_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let deadline = config
        .max_seconds
        .and_then(|s| tokio::time::Instant::now().checked_add(Duration::from_secs(s)));
    let mut inflight: Option<InFlight> = None;
    let mut decision_epoch = DecisionEpoch::default();
    let mut consecutive_malformed = 0u32;
    let mut session_error = None;
    let mut terminal_state = None;

    loop {
        if stop.load(Ordering::Relaxed) {
            break;
        }
        if let Some(deadline) = deadline {
            if tokio::time::Instant::now() >= deadline {
                break;
            }
        }
        tokio::select! {
            msg = stream.next() => match msg {
                Some(Ok(Message::Text(text))) => match serde_json::from_str::<ServerMessage>(&text) {
                    Ok(ServerMessage::Mission { tick, state }) => {
                        let changed = DecisionEpoch::mission_changed(mission_client.state.as_ref(), &state);
                        if let Err(error) = mission_client.observe(tick, state) {
                            session_error = Some(Error::Transport(format!("invalid mission: {error}")));
                            break;
                        }
                        if changed {
                            decision_epoch.advance();
                        }
                        summary.mission = mission_client.state.as_ref().map(MissionReceipt::from);
                        if let (Some(trace), Some(state)) = (timeline.as_mut(), mission_client.state.as_ref()) {
                            trace.mission(tick, state);
                        }
                        if let Some(state) = mission_client.state.as_ref().filter(|state| terminal_mission(state)) {
                            terminal_state = Some(state.clone());
                            break;
                        }
                        if let Some(ready) = mission_client.readiness(me) {
                            let wire = serde_json::to_string(&ClientMessage::MissionReady(ready)).map_err(transport_err)?;
                            if !send_text(&mut sink, wire).await {
                                session_error = Some(Error::Transport("mission readiness was not accepted in time".into()));
                                break;
                            }
                        }
                        if let Some(request) = mission_client.continuation(me) {
                            let wire = serde_json::to_string(&ClientMessage::MissionContinue(request)).map_err(transport_err)?;
                            if !send_text(&mut sink, wire).await {
                                session_error = Some(Error::Transport("mission continue was not accepted in time".into()));
                                break;
                            }
                        }
                    }
                    Ok(ServerMessage::Loadout(next)) => {
                        let valid = next.validate_for(me, loadout.as_ref());
                        if let Err(error) = valid {
                            session_error = Some(Error::Transport(format!("invalid loadout: {error}")));
                            break;
                        }
                        loadout = Some(next);
                    }
                    Ok(ServerMessage::Welcome { player_id, .. }) => {
                        me = player_id;
                        summary.player_id = player_id;
                    }
                    Ok(ServerMessage::Snapshot(snapshot)) => {
                        decision_epoch.observe_snapshot(me, last.as_ref(), &snapshot);
                        summary.snapshots += 1;
                        if let Some(id) = me {
                            if let Some(p) = snapshot.players.iter().find(|p| p.id == id) {
                                my_name = p.name.clone();
                            }
                        }
                        last = Some(snapshot);
                    }
                    Ok(ServerMessage::Event(event)) => {
                        let tick = last.as_ref().map(|s| s.tick).unwrap_or(0);
                        if let Some(id) = me {
                            hits.ingest(id, tick, &event);
                            if let (Some(trace), Some(state)) = (timeline.as_mut(), mission_client.state.as_ref()) {
                                trace.event(tick, state, id, &event);
                            }
                        }
                        if let GameEvent::Frag { killer, victim, .. } = &event {
                            if *killer == my_name {
                                summary.frags += 1;
                            }
                            if record.is_none() && *victim == my_name {
                                summary.deaths += 1;
                            }
                        }
                    }
                    // The brain does not predict, so an ack is nothing to act on.
                    Ok(ServerMessage::Ack { .. }) => {}
                    // Records are an observation surface, never combat input.
                    Ok(ServerMessage::Record(next)) => {
                        if let Err(error) = next.validate_for(me, record.as_ref()) {
                            session_error = Some(Error::Transport(format!("invalid participant record: {error}")));
                            break;
                        }
                        set_record_counts(&mut summary, &next.total);
                        record = Some(next);
                    }
                    // Geometry belongs to the local controller, never a paid
                    // per-frame decision. Reject invalid worlds before driving.
                    Ok(ServerMessage::MapInfo { map_id, m02_objectives, m02_side_ward, m03, m04, m05, m06, m07, m08, m09, m10, map_name, solids, half_extent, geometry_version, presentation, mission, .. }) => {
                        decision_epoch.advance();
                        if let Err(error) = fragr_server::protocol::validate_map_presentation(presentation.as_ref(), &solids) {
                            session_error = Some(Error::Transport(format!("invalid map presentation: {error}")));
                            break;
                        }
                        tracing::debug!("map: {map_name}");
                        if let Err(error) = mission_client.replace_map_with_id(map_id, m02_objectives, m02_side_ward, mission.as_ref(), half_extent, &solids, presentation.as_ref()) {
                            session_error = Some(Error::Transport(format!("invalid mission map: {error}")));
                            break;
                        }
                        mission_geometry = mission.clone();
                        if let Err(error) = mission_client.replace_map_with_m03(m03.as_ref(), half_extent, &solids, presentation.as_ref()) {
                            session_error = Some(Error::Transport(format!("invalid M03 mission map: {error}")));
                            break;
                        }
                        if let Err(error) = mission_client.replace_map_with_m04(m04.as_ref(), half_extent, &solids, presentation.as_ref()) {
                            session_error = Some(Error::Transport(format!("invalid M04 mission map: {error}")));
                            break;
                        }
                        if let Err(error) = fragr_server::protocol::validate_map_geometry(half_extent, &solids, geometry_version) {
                            session_error = Some(Error::Transport(format!("invalid navigation map: {error}")));
                            break;
                        }
                        if let Err(error) = mission_client.replace_map_with_m05(m05.as_ref(), half_extent, &solids, presentation.as_ref()) {
                            session_error = Some(Error::Transport(format!("invalid navigation map: {error}")));
                            break;
                        }
                        if let Err(error) = mission_client.replace_map_with_m06(m06.as_ref(), half_extent, &solids, presentation.as_ref()) {
                            session_error = Some(Error::Transport(format!("invalid M06 mission map: {error}")));
                            break;
                        }
                        if let Err(error) = mission_client.replace_map_with_m08(m08.as_ref(), half_extent, &solids, presentation.as_ref()) {
                            session_error = Some(Error::Transport(format!("invalid M08 mission map: {error}")));
                            break;
                        }
                        if let Err(error) = mission_client.replace_map_with_m07(m07.as_ref(), half_extent, &solids, presentation.as_ref()) {
                            session_error = Some(Error::Transport(format!("invalid M07 mission map: {error}")));
                            break;
                        }
                        if let Err(error)=mission_client.replace_map_with_m09(m09.as_ref(),half_extent,&solids,presentation.as_ref()) {
                            session_error=Some(Error::Transport(format!("invalid M09 mission map: {error}")));break;
                        }
                        if let Err(error) = mission_client.replace_map_with_m10(m10.as_ref(),half_extent,&solids,presentation.as_ref()) {session_error = Some(Error::Transport(format!("invalid M10 mission map: {error}")));break;}
                        let arena = fragr_server::movement::Arena { half: half_extent, solids };
                        let built = tokio::task::spawn_blocking(move || {
                            fragr_server::navigation::Navigation::shared(arena)
                        }).await.map_err(|_| "navigation worker failed").and_then(|result| result);
                        match built {
                            Ok(world) => navigation = Some(world),
                            Err(error) => {
                                tracing::warn!("invalid navigation map: {error}");
                                session_error = Some(Error::Transport(format!("invalid navigation map: {error}")));
                                break;
                            }
                        }
                        navigator.clear();
                        last = None;
                        if mission.is_none() {
                            summary.mission = None;
                        }
                    }
                    Ok(ServerMessage::Error { code, message }) => {
                        tracing::warn!("server rejected: {code}: {message}");
                        if code == "unsupported_geometry" || code == "unsupported_gameplay" || code == "party_full" {
                            session_error = Some(Error::Transport(message));
                            break;
                        }
                    }
                    Err(error) => {
                        session_error = Some(Error::Transport(format!("invalid server message: {error}")));
                        break;
                    }
                },
                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                Some(Ok(_)) => {}
            },
            _ = micro.tick() => {
                if let (Some(id), Some(snapshot)) = (me, last.as_ref()) {
                    if inflight.is_some() {
                        if let Some(telemetry) = observe(id, snapshot, &mut hits) {
                            plan = fallback_plan(&telemetry, Source::Local);
                        }
                    }
                    constrain_campaign_equipment(&mut plan, mission_client.state.is_some(), loadout.as_ref());
                    let live_solids = mission_client.live_visibility_solids();
                    let alive = snapshot.players.iter().any(|player| player.id == id && player.hp > 0);
                    let action = if !alive {
                        navigator.clear();
                        Action::default()
                    } else { match (mission_client.state.as_ref(), navigation.as_ref()) {
                        (Some(_), Some(world)) => campaign_micro_action_with_solids(&plan, id, snapshot, world, live_solids.as_deref()),
                        (_, Some(world)) if snapshot.flags.is_some() => crate::plan::ctf_micro_action_in_world(&plan, id, snapshot, world),
                        _ => micro_action(&plan, id, snapshot),
                    }};
                    let action = if let (Some(_), Some(world)) = (mission_client.state.as_ref(), navigation.as_ref()) {
                        fragr_server::inventory::control_action_with_target_filter(id, snapshot, loadout.as_ref(), action, true, |mine, other| campaign_enemy_engageable_with_solids(world, mine, other, live_solids.as_deref()))
                    } else if let Some(world) = navigation.as_ref().filter(|_| snapshot.flags.is_some()) {
                        fragr_server::inventory::control_action_with_target_filter(id, snapshot, loadout.as_ref(), action, true, |mine, other| target_visible(world, mine, other))
                    } else {
                        fragr_server::inventory::control_action_with_objective(id, snapshot, loadout.as_ref(), action, snapshot.flags.is_some())
                    };
                    let action = if mission_client.state.as_ref().is_some_and(|state| !matches!(state.phase, MissionPhase::Briefing | MissionPhase::Departed)) {
                        stall.apply(id, snapshot, action)
                    } else {
                        stall = crate::plan::StallWatch::default();
                        action
                    };
                    let intent = action.clone();
                    let action = navigation.as_ref().map_or_else(Action::default, |world| {
                        mission_client.steer(&mut navigator, world, id, snapshot, action)
                    });
                    let text = serde_json::to_string(&ClientMessage::Action(action.clone()))
                        .map_err(transport_err)?;
                    if !send_text(&mut sink, text).await {
                        break;
                    }
                    if let (Some(trace), Some(state)) = (timeline.as_mut(), mission_client.state.as_ref()) {
                        trace.sample(id, snapshot, state, mission_geometry.as_ref(), loadout.as_ref(), &plan, &intent, &action);
                    }
                    summary.actions_sent += 1;
                }
            },
            _ = macro_tick.tick() => {
                let Some(id) = me else { continue };
                let Some(snapshot) = last.as_ref() else { continue };
                let Some(telemetry) = observe(id, snapshot, &mut hits) else { continue };
                summary.last_state = Some(telemetry.render());
                if inflight.is_some() || !paid_enabled || !brain_worth_asking(&telemetry) || !mission_client.participating(id) {
                    let source = if config.provider.is_paid() && !paid_enabled {
                        Source::Budget
                    } else if config.provider.is_local_model() && !paid_enabled {
                        Source::Failure
                    } else {
                        Source::Local
                    };
                    plan = fallback_plan(&telemetry, source);
                    summary.decisions_local += 1;
                    if let Some(wire) = display_behavior_wire(&mut published_stance, plan.stance) {
                        if !send_text(&mut sink, wire).await {
                            break;
                        }
                    }
                    continue;
                }
                let questions = if mission_client.state.is_some() {
                    let Some(equipment) = loadout.as_ref() else {
                        plan = fallback_plan(&telemetry, Source::Local);
                        summary.decisions_local += 1;
                        continue;
                    };
                    Arc::new(campaign_questions(&equipment.weapons))
                } else {
                    arena_questions.clone()
                };
                let questions = if config.provider == Provider::Ollama {
                    Arc::new(stance_questions((*questions).clone()))
                } else {
                    questions
                };
                // The initial request must also have a useful local plan;
                // do not hold the initial stance while a model loads intent.
                let fallback = fallback_plan(&telemetry, Source::Failure);
                if plan.source == Source::Initial {
                    plan = fallback_plan(&telemetry, Source::Local);
                }
                let (tx, rx) = oneshot::channel();
                let handle = spawn_decision(
                    transport.clone(),
                    budget.clone(),
                    questions,
                    Asker::from_config(&config),
                    {
                        let mut with_memory = telemetry.clone();
                        with_memory.recent = memory.clone();
                        if let (Some(_), Some(world)) = (mission_client.state.as_ref(), navigation.as_ref()) {
                            let live_solids = mission_client.live_visibility_solids();
                            align_campaign_enemy(&mut with_memory, id, snapshot, world, live_solids.as_deref());
                        }
                        let enemy_visible = mission_client.state.as_ref().map(|_| true);
                        decision_state(&with_memory, mission_client.state.as_ref(), loadout.as_ref(), enemy_visible)
                    },
                    fallback,
                    config.gate,
                    next_roll(&mut roll_state),
                    tx,
                );
                inflight = Some((rx, handle, decision_epoch.0));
            },
            answer = async { (&mut inflight.as_mut().expect("guarded by the branch condition").0).await }, if inflight.is_some() => {
                let requested_epoch = inflight.take().expect("guarded by the branch condition").2;
                let outcome = match answer {
                    Ok((outcome, ms)) => {
                        if matches!(outcome, Outcome::Decided(_) | Outcome::Failed(..)) {
                            summary.decision_latency.push(ms);
                        }
                        outcome
                    }
                    Err(_) => {
                        // The blocking task ended without answering (a panic).
                        summary.decisions_failed += 1;
                        tracing::warn!("decision task ended without an answer; local rules this cycle");
                        continue;
                    }
                };
                let fresh = me.and_then(|id| last.as_ref().and_then(|snapshot| observe(id, snapshot, &mut hits)));
                if matches!(outcome, Outcome::Decided(_)) && !decision_epoch.accepts(requested_epoch) {
                    summary.decisions_discarded += 1;
                    summary.fallbacks += 1;
                    if let Some(telemetry) = fresh.as_ref() {
                        plan = fallback_plan(telemetry, Source::Local);
                    }
                    consecutive_malformed = 0;
                    if backoff_level > 0 {
                        backoff_level = 0;
                        macro_tick = tokio::time::interval_at(
                            tokio::time::Instant::now() + base_interval,
                            base_interval,
                        );
                        macro_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                    }
                    continue;
                }
                match outcome {
                    Outcome::Decided(mut decided) => {
                        if decided.source != Source::Remote {
                            if let Some(telemetry) = fresh.as_ref() {
                                decided.stance = fallback_plan(telemetry, decided.source).stance;
                            }
                        }
                        if config.provider == Provider::Ollama {
                            if let Some(telemetry) = fresh.as_ref() {
                                let local = fallback_plan(telemetry, decided.source);
                                decided.weapon = local.weapon;
                                decided.danger = local.danger;
                            }
                        }
                        consecutive_malformed = 0;
                        match decided.source {
                            Source::Remote => summary.decisions_remote += 1,
                            _ => {
                                summary.decisions_low_confidence += 1;
                                summary.fallbacks += 1;
                            }
                        }
                        remember(&mut memory, plan_word(&decided));
                        plan = decided;
                        if backoff_level > 0 {
                            backoff_level = 0;
                            macro_tick = tokio::time::interval_at(
                                tokio::time::Instant::now() + base_interval,
                                base_interval,
                            );
                            macro_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                        }
                        if let Some(wire) =
                            display_behavior_wire(&mut published_stance, plan.stance)
                        {
                            if !send_text(&mut sink, wire).await {
                                break;
                            }
                        }
                    }
                    Outcome::Refused(err, fallback) => {
                        summary.budget_refusals += 1;
                        summary.fallbacks += 1;
                        if paid_enabled {
                            tracing::warn!("brain off for the rest of the run: {err}");
                            summary.brain_disabled = Some(err.to_string());
                        }
                        paid_enabled = false;
                        plan = fresh.as_ref().map_or(fallback, |telemetry| fallback_plan(telemetry, Source::Budget));
                        if let Some(wire) =
                            display_behavior_wire(&mut published_stance, plan.stance)
                        {
                            if !send_text(&mut sink, wire).await {
                                break;
                            }
                        }
                    }
                    Outcome::Failed(err, fallback) => {
                        summary.decisions_failed += 1;
                        summary.fallbacks += 1;
                        if matches!(err, Error::Timeout(_)) {
                            summary.timeouts += 1;
                        }
                        let unreadable = matches!(err, Error::Malformed(_) | Error::Io(_));
                        consecutive_malformed = if unreadable { consecutive_malformed + 1 } else { 0 };
                        if is_fatal(&err) || consecutive_malformed >= MAX_CONSECUTIVE_MALFORMED {
                            summary.fatal_failures += 1;
                            summary.brain_disabled = Some(err.to_string());
                            paid_enabled = false;
                            tracing::warn!("brain off for the rest of the run: {err}");
                        } else if is_retryable(&err) && backoff_level < MAX_BACKOFF_LEVEL {
                            backoff_level += 1;
                            summary.backoffs += 1;
                            let period = backoff_interval(base_interval, backoff_level);
                            macro_tick = tokio::time::interval_at(tokio::time::Instant::now() + period, period);
                            macro_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                            tracing::warn!("brain call failed, backing off to {period:?}: {err}");
                        } else {
                            tracing::warn!("brain call failed, local rules this cycle: {err}");
                        }
                        plan = fresh.as_ref().map_or(fallback, |telemetry| fallback_plan(telemetry, Source::Failure));
                        if let Some(wire) =
                            display_behavior_wire(&mut published_stance, plan.stance)
                        {
                            if !send_text(&mut sink, wire).await {
                                break;
                            }
                        }
                    }
                }
            },
        }
    }
    if let Some(state) = terminal_state.as_ref() {
        match drain_terminal_record(&mut stream, me, state, &mut record, &mut summary).await {
            Ok(complete) => summary.terminal_record_complete = Some(complete),
            Err(error) => {
                summary.terminal_record_complete = Some(false);
                session_error = Some(error);
            }
        }
    }
    let _ = sink.close().await;
    // Let an in-flight decision finish so its charge is in the ledger before
    // the totals are read; a panic or a hang is bounded, not fatal.
    if let Some((_, handle, _)) = inflight.take() {
        let _ = tokio::time::timeout(DRAIN_TIMEOUT, handle).await;
    }
    {
        let guard = lock(&budget);
        summary.run_usd = guard.run_usd();
        summary.total_usd = guard.total_usd();
    }
    constrain_campaign_equipment(&mut plan, mission_client.state.is_some(), loadout.as_ref());
    summary.last_plan = Some(plan);
    summary.decision_latency.finish();
    summary.elapsed_seconds = started.elapsed().as_secs_f64();
    if summary.elapsed_seconds > 0.0 {
        summary.decisions_per_second =
            summary.decision_latency.samples as f64 / summary.elapsed_seconds;
    }
    if let (Some(trace), Some(path)) = (timeline.as_ref(), config.timeline_path.as_ref()) {
        trace.write(path, me)?;
    }
    if let Some(error) = session_error {
        Err(error)
    } else {
        Ok(summary)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::budget::{Caps, Pricing, Refusal};
    use crate::provider::fakes::{push_answers, FakeTransport};
    use crate::provider::HttpResponse;
    use crate::telemetry::fixtures::{player, snapshot};
    use fragr_server::protocol::{
        AmmoCount, AmmoPool, CampaignRules, CampaignRunState, CombatCounts, LoadoutState,
        MissionMember, PlayerRecord, RecordScope, RecordStatus, WeaponType,
        RECORD_TICKS_PER_SECOND, RECORD_VERSION,
    };
    use fragr_server::run::{run_server, ServerOptions};
    use fragr_server::sim::{MapKind, MatchConfig};

    #[test]
    fn authoritative_record_counts_campaign_deaths_without_frag_events() {
        let mut summary = BotSummary::default();
        let mut total = CombatCounts {
            deaths: 3,
            ..CombatCounts::default()
        };
        total.weapons[WeaponType::Tack.index()].kills = 7;
        set_record_counts(&mut summary, &total);
        assert_eq!(summary.deaths, 3);
        assert_eq!(summary.kills, Some(7));
        assert_eq!(summary.frags, 0);
    }

    #[test]
    fn terminal_campaign_state_stops_only_after_success_or_exhaustion() {
        let id = Uuid::from_u128(1);
        let mut state = MissionState {
            id: MissionId::RecallNotice,
            run: Some(CampaignRunState {
                id: Uuid::from_u128(2),
                status: CampaignRunStatus::Playing,
                continues: 1,
                level_start_continues: 3,
            }),
            rules: CampaignRules::new(CampaignDifficulty::Standard),
            attempt: 3,
            phase: MissionPhase::FindTransfer,
            changed_at: 1,
            party: vec![MissionMember {
                id,
                name: "Brain".into(),
                ready: true,
                alive: true,
                aboard: false,
            }],
            prompts: vec![],
            m02: None,
            m03: None,
            m04: None,
            m05: None,
            m06: None,
            m08: None,
            m07: None,
            m09: None,
            m10: None,
        };
        state.validate(1).unwrap();
        assert!(!terminal_mission(&state));
        state.run.as_mut().unwrap().status = CampaignRunStatus::Continue;
        state.party[0].alive = false;
        state.validate(1).unwrap();
        assert!(
            !terminal_mission(&state),
            "the participant still has a retry"
        );
        state.run.as_mut().unwrap().status = CampaignRunStatus::Failed;
        state.run.as_mut().unwrap().continues = 0;
        state.attempt = 4;
        state.validate(1).unwrap();
        assert!(terminal_mission(&state));
        state.run.as_mut().unwrap().status = CampaignRunStatus::Complete;
        state.phase = MissionPhase::Departed;
        state.party[0].alive = true;
        state.validate(1).unwrap();
        assert!(terminal_mission(&state));
    }

    fn completed_mission_and_record() -> (MissionState, PlayerRecord) {
        let id = Uuid::from_u128(1);
        let run = CampaignRunState {
            id: Uuid::from_u128(2),
            status: CampaignRunStatus::Complete,
            continues: 3,
            level_start_continues: 3,
        };
        let state = MissionState {
            id: MissionId::RecallNotice,
            run: Some(run),
            rules: CampaignRules::new(CampaignDifficulty::Standard),
            attempt: 1,
            phase: MissionPhase::Departed,
            changed_at: 15,
            party: vec![MissionMember {
                id,
                name: "Brain".into(),
                ready: true,
                alive: true,
                aboard: true,
            }],
            prompts: vec![],
            m02: None,
            m03: None,
            m04: None,
            m05: None,
            m06: None,
            m08: None,
            m07: None,
            m09: None,
            m10: None,
        };
        state.validate(20).unwrap();
        let mut total = CombatCounts {
            alive_ticks: 10,
            ..CombatCounts::default()
        };
        total.weapons[WeaponType::Tack.index()].attacks = 1;
        total.weapons[WeaponType::Tack.index()].damaging_attacks = 1;
        total.weapons[WeaponType::Tack.index()].kills = 1;
        let record = PlayerRecord {
            mission_elapsed_ticks: None,
            version: RECORD_VERSION,
            session_id: Uuid::from_u128(3),
            player_id: id,
            round: 1,
            tick: 20,
            entered_at: 0,
            round_started_at: 0,
            ticks_per_second: RECORD_TICKS_PER_SECOND,
            map_id: 7,
            map_name: "Recall Notice".into(),
            role: Role::Agent,
            scope: RecordScope::Mission {
                mission: state.id,
                attempt: state.attempt,
                rules: state.rules,
                run: state.run,
            },
            status: RecordStatus::Complete,
            total: total.clone(),
            attempt: total,
        };
        record.validate_for(Some(id), None).unwrap();
        (state, record)
    }

    #[tokio::test]
    async fn delayed_terminal_record_wins_over_stale_record_and_old_grace() {
        let (state, final_record) = completed_mission_and_record();
        let mut stale = final_record.clone();
        stale.tick = 10;
        stale.status = RecordStatus::Active;
        stale.total.weapons[WeaponType::Tack.index()].kills = 0;
        stale.total.weapons[WeaponType::Tack.index()].damaging_attacks = 0;
        stale.total.weapons[WeaponType::Tack.index()].attacks = 0;
        stale.attempt = stale.total.clone();
        if let RecordScope::Mission { run, .. } = &mut stale.scope {
            run.as_mut().unwrap().status = CampaignRunStatus::Playing;
        }
        stale.validate_for(Some(stale.player_id), None).unwrap();
        assert!(!terminal_record_matches(&state, &stale));
        assert!(terminal_record_matches(&state, &final_record));
        let stale_wire = serde_json::to_string(&ServerMessage::Record(stale)).unwrap();
        let final_wire = serde_json::to_string(&ServerMessage::Record(final_record)).unwrap();
        let mut stream = Box::pin(futures_util::stream::unfold(0, move |step| {
            let stale_wire = stale_wire.clone();
            let final_wire = final_wire.clone();
            async move {
                match step {
                    0 => Some((Ok(Message::Text(stale_wire)), 1)),
                    1 => {
                        tokio::time::sleep(Duration::from_millis(650)).await;
                        Some((Ok(Message::Text(final_wire)), 2))
                    }
                    _ => None,
                }
            }
        }));
        let mut summary = BotSummary::default();
        let mut received = None;
        let started = tokio::time::Instant::now();
        let complete = drain_terminal_record(
            &mut stream,
            Some(state.party[0].id),
            &state,
            &mut received,
            &mut summary,
        )
        .await
        .unwrap();
        assert!(complete);
        assert!(started.elapsed() >= Duration::from_millis(650));
        assert_eq!(summary.kills, Some(1));
    }

    #[tokio::test]
    async fn missing_terminal_record_times_out_incomplete() {
        let (state, _) = completed_mission_and_record();
        let mut stream = futures_util::stream::pending();
        let mut summary = BotSummary::default();
        let mut received = None;
        let complete = drain_terminal_record(
            &mut stream,
            Some(state.party[0].id),
            &state,
            &mut received,
            &mut summary,
        )
        .await
        .unwrap();
        assert!(!complete);
        assert_eq!(summary.kills, None);
    }

    #[test]
    fn campaign_decision_state_carries_validated_stakes_and_equipment() {
        let id = Uuid::from_u128(1);
        let state = MissionState {
            id: MissionId::RecallNotice,
            run: Some(CampaignRunState {
                id: Uuid::from_u128(2),
                status: CampaignRunStatus::Playing,
                continues: 3,
                level_start_continues: 3,
            }),
            rules: CampaignRules::new(CampaignDifficulty::Severe),
            attempt: 1,
            phase: MissionPhase::FindTransfer,
            changed_at: 1,
            party: vec![MissionMember {
                id,
                name: "Brain".into(),
                ready: true,
                alive: true,
                aboard: false,
            }],
            prompts: vec![],
            m02: None,
            m03: None,
            m04: None,
            m05: None,
            m06: None,
            m08: None,
            m07: None,
            m09: None,
            m10: None,
        };
        state.validate(1).unwrap();
        let loadout = LoadoutState {
            player_id: id,
            tick: 1,
            selected: WeaponType::Tack,
            weapons: vec![WeaponType::Fists, WeaponType::Tack],
            // Six bullets, the magazine-era fixture's loaded rounds.
            ammo: AmmoPool::ALL
                .into_iter()
                .map(|pool| AmmoCount {
                    pool,
                    rounds: if pool == AmmoPool::Bullets { 6 } else { 0 },
                })
                .collect(),
            personal_claims: vec![],
            dry_fire_count: 0,
            grenades: 0,
            proximity_mines: 0,
        };
        loadout.validate_for(Some(id), None).unwrap();
        let mut proposed = Plan {
            weapon: Some(WeaponType::Rail),
            ..Plan::default()
        };
        constrain_campaign_equipment(&mut proposed, true, Some(&loadout));
        assert_eq!(proposed.weapon, None);
        proposed.weapon = Some(WeaponType::Tack);
        constrain_campaign_equipment(&mut proposed, true, Some(&loadout));
        assert_eq!(proposed.weapon, Some(WeaponType::Tack));
        let snap = snapshot(
            1,
            vec![
                player("Brain", id, 0.0, 0.0, 100, "tack"),
                player("Guard", Uuid::from_u128(3), 8.0, 0.0, 60, "tack"),
            ],
            vec![],
        );
        let telemetry = observe(id, &snap, &mut RecentHits::default()).unwrap();
        let result = decision_state(&telemetry, Some(&state), Some(&loadout), Some(false));
        assert_eq!(result["mission"]["phase"], "find_transfer");
        assert_eq!(result["mission"]["difficulty"], "severe");
        assert_eq!(result["mission"]["status"], "playing");
        assert_eq!(result["mission"]["attempt"], 1);
        assert_eq!(result["mission"]["continues"], 3);
        assert_eq!(result["equipment"]["weapons"].as_array().unwrap().len(), 2);
        assert_eq!(result["enemy"]["visible"], false);
        assert!(result["self"].get("score").is_none());
        assert!(result.get("clock").is_none());
        let arena = decision_state(&telemetry, None, None, None);
        assert!(arena.get("mission").is_none());
        assert!(arena.get("clock").is_some());
    }

    #[test]
    fn campaign_decision_enemy_matches_the_exposed_combat_target() {
        use fragr_server::movement::{Arena, Solid};
        use fragr_server::navigation::Navigation;
        use fragr_server::protocol::{CampaignActor, EnemyKind, EnemyPhase};
        let id = Uuid::from_u128(1);
        let mut mine = player("Brain", id, 0.0, 0.0, 100, "tack");
        mine.campaign = Some(CampaignActor::Participant {});
        let union = Some(CampaignActor::Union {
            kind: EnemyKind::Clerk,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
        });
        let mut hidden = player("Hidden", Uuid::from_u128(2), 10.0, 0.0, 60, "tack");
        hidden.campaign = union;
        let mut exposed = player("Exposed", Uuid::from_u128(3), 8.0, 8.0, 60, "flechette");
        exposed.campaign = union;
        let snap = snapshot(1, vec![mine, hidden, exposed], vec![]);
        let world = Navigation::new(Arena {
            half: 24.0,
            solids: vec![Solid::from_center(5.0, 0.0, 0.5, 3.0)],
        })
        .unwrap();
        let mut telemetry = observe(id, &snap, &mut RecentHits::default()).unwrap();
        assert_eq!(telemetry.enemy.as_ref().unwrap().name, "Hidden");
        align_campaign_enemy(&mut telemetry, id, &snap, &world, None);
        assert_eq!(telemetry.enemy.as_ref().unwrap().name, "Exposed");
        let mission = MissionState {
            id: MissionId::RecallNotice,
            run: None,
            rules: CampaignRules::default(),
            attempt: 1,
            phase: MissionPhase::FindTransfer,
            changed_at: 1,
            party: vec![],
            prompts: vec![],
            m02: None,
            m03: None,
            m04: None,
            m05: None,
            m06: None,
            m08: None,
            m07: None,
            m09: None,
            m10: None,
        };
        let state = decision_state(&telemetry, Some(&mission), None, Some(true));
        assert_eq!(state["enemy"]["weapon"], "flechette");
        assert_eq!(state["enemy"]["visible"], true);
        let moved_cover = [Solid::from_center(5.0, 8.0, 0.5, 3.0)];
        align_campaign_enemy(&mut telemetry, id, &snap, &world, Some(&moved_cover));
        assert_eq!(
            telemetry.enemy.as_ref().unwrap().name,
            "Hidden",
            "decision state follows physical cover after the parked body moves"
        );
    }

    async fn boot_server(bots: usize) -> (String, tokio::sync::oneshot::Sender<()>) {
        boot_server_with_mode(bots, fragr_server::protocol::GameMode::Ffa).await
    }

    async fn boot_server_with_mode(
        bots: usize,
        mode: fragr_server::protocol::GameMode,
    ) -> (String, tokio::sync::oneshot::Sender<()>) {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let options = ServerOptions {
            campaign_run: false,
            difficulty: None,
            authored: None,
            bind: "127.0.0.1:0".to_string(),
            bots,
            bot_policy: fragr_server::bot_fill::BotPolicy::Fixed,
            fill_target: 0,
            map: MapKind::default(),
            map_rotate: false,
            solo_broadcast: false,
            match_config: Some(MatchConfig {
                rules: fragr_server::rules::RuleSet::new(mode, &[], false).unwrap(),
                warmup_ticks: 1,
                boss_spawn_ticks: None,
                compliance_ping_ticks: None,
                ..MatchConfig::default()
            }),
            seed: 1,
            status_every_s: 0,
            join_secret: None,
            access: Default::default(),
            console: false,
        };
        tokio::spawn(async move {
            let _ = run_server(
                options,
                async move {
                    let _ = shutdown_rx.await;
                },
                Some(ready_tx),
            )
            .await;
        });
        let addr = tokio::time::timeout(Duration::from_secs(5), ready_rx)
            .await
            .expect("bind in time")
            .expect("server bound");
        (format!("ws://{addr}"), shutdown_tx)
    }

    fn config(url: &str, provider: Provider, seconds: u64) -> BotConfig {
        BotConfig {
            server_url: url.to_string(),
            name: "Brain-1".to_string(),
            provider,
            model: provider.default_model().to_string(),
            api_key: provider.is_paid().then(|| "sk_test".to_string()),
            model_url: provider.default_base_url().map(str::to_string),
            decision_budget: Duration::from_secs(2),
            decision_hz: 5.0,
            gate: Gate::default(),
            max_seconds: Some(seconds),
            timeline_path: None,
            body: fragr_server::protocol::BodyKind::Synthetic,
        }
    }

    fn budget(run_usd: f64) -> Arc<Mutex<Budget>> {
        let path = std::env::temp_dir().join(format!("fragr-brain-bot-{}.jsonl", Uuid::new_v4()));
        Arc::new(Mutex::new(
            Budget::with_ledger(
                Caps {
                    run_usd,
                    total_usd: None,
                    run_calls: None,
                },
                Pricing::default(),
                &path,
            )
            .unwrap(),
        ))
    }

    /// A generous outer bound for tests that drive their own end through
    /// `stop` once they observe real readiness, or that return early on their
    /// own (an invalid map, a stop flag already set). Connect and warmup
    /// latency under contention is unbounded relative to the fixed decision
    /// cadence a test asserts on, so this constant is never the thing a
    /// passing run actually waits out; `wait_for` bounds the setup side.
    const SAFETY_NET_SECONDS: u64 = 20;

    #[test]
    fn decision_epoch_tracks_life_round_and_map_without_rejecting_motion() {
        let id = Uuid::from_u128(1);
        let initial = snapshot(1, vec![player("Brain", id, 0.0, 0.0, 100, "rail")], vec![]);
        let mut epoch = DecisionEpoch::default();
        epoch.observe_snapshot(Some(id), None, &initial);
        assert!(epoch.accepts(0));
        let mut moved = initial.clone();
        moved.tick = 2;
        moved.players[0].x = 5.0;
        epoch.observe_snapshot(Some(id), Some(&initial), &moved);
        assert!(epoch.accepts(0), "ordinary movement keeps intent usable");
        let mut dead = moved.clone();
        dead.players[0].hp = 0;
        epoch.observe_snapshot(Some(id), Some(&moved), &dead);
        assert!(!epoch.accepts(0));
        let death = epoch.0;
        epoch.observe_snapshot(Some(id), Some(&dead), &moved);
        assert!(!epoch.accepts(death), "respawn starts a new life");
        let alive = epoch.0;
        let mut ended = moved.clone();
        ended.round_state = Some("Ended".into());
        epoch.observe_snapshot(Some(id), Some(&moved), &ended);
        assert!(!epoch.accepts(alive));
        let round = epoch.0;
        let mut replaced = ended.clone();
        replaced.map_id += 1;
        epoch.observe_snapshot(Some(id), Some(&ended), &replaced);
        assert!(!epoch.accepts(round));
        let map = epoch.0;
        epoch.advance();
        assert!(
            !epoch.accepts(map),
            "explicit mission transitions invalidate intent"
        );
        let mut joined = replaced.clone();
        joined
            .players
            .push(player("human", Uuid::from_u128(2), 10.0, 0.0, 100, "rail"));
        let before_join = epoch.0;
        epoch.observe_snapshot(Some(id), Some(&replaced), &joined);
        assert!(
            epoch.accepts(before_join),
            "unadvertised peer does not change coordination"
        );
        let mut advertised = joined.clone();
        advertised.players[1].behavior = Some("hold_angle".into());
        epoch.observe_snapshot(Some(id), Some(&joined), &advertised);
        assert!(
            !epoch.accepts(before_join),
            "compatible peer changes role election"
        );
        let before_stance = epoch.0;
        let mut updated = advertised.clone();
        updated.players[1].behavior = Some("push_enemy".into());
        updated.players.reverse();
        epoch.observe_snapshot(Some(id), Some(&advertised), &updated);
        assert!(
            epoch.accepts(before_stance),
            "stance and snapshot order do not change compatibility"
        );
    }

    /// Hold inference until the socket fixture has observed useful fallback.
    struct HeldModel {
        started: AtomicBool,
        release: AtomicBool,
        finished: AtomicBool,
    }

    impl Transport for HeldModel {
        fn send(&self, _request: &crate::provider::HttpRequest) -> Result<HttpResponse, Error> {
            self.started.store(true, Ordering::SeqCst);
            let limit = std::time::Instant::now() + Duration::from_secs(10);
            while !self.release.load(Ordering::SeqCst) {
                if std::time::Instant::now() >= limit {
                    return Err(Error::Timeout("fixture never released inference".into()));
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            self.finished.store(true, Ordering::SeqCst);
            Ok(HttpResponse {
                status: 200,
                body: letter_a().to_string().into_bytes(),
            })
        }
    }

    #[tokio::test]
    async fn delayed_model_survives_tram_motion_but_not_objective_or_retry_changes() {
        use fragr_server::protocol::{
            M05ObjectiveState, M05TramPhase, M05TramState, M05WorkerState, MissionObjective,
            MissionObjectiveAction, Region3,
        };
        let mut mission = MissionState {
            id: MissionId::NoForwardingAddress,
            run: None,
            rules: CampaignRules::default(),
            attempt: 1,
            phase: MissionPhase::InProgress,
            changed_at: 1,
            party: vec![MissionMember {
                id: Uuid::from_u128(1),
                name: "Brain".into(),
                ready: true,
                alive: true,
                aboard: false,
            }],
            prompts: vec![],
            m02: None,
            m03: None,
            m04: None,
            m05: Some(M05ObjectiveState {
                completed: vec![],
                current: Some(MissionObjective {
                    id: "roof_crossed".into(),
                    action: MissionObjectiveAction::Arrival {
                        region: Region3 {
                            min: [0.0; 3],
                            max: [1.0; 3],
                        },
                        feet: [0.0; 3],
                    },
                }),
                workshop_secured: true,
                group_released: true,
                freight_open: false,
                captives: vec![M05WorkerState {
                    id: "splice".into(),
                    feet: [0.0; 3],
                }],
                tram: M05TramState {
                    phase: M05TramPhase::Moving,
                    feet: [0.0; 3],
                    tick: 1,
                },
                carried_recall_cars: vec![],
                carried_patients: vec![],
                carried_photos: 0,
            }),
            m06: None,
            m08: None,
            m07: None,
            m09: None,
            m10: None,
        };
        let mut epoch = DecisionEpoch::default();
        if DecisionEpoch::mission_changed(None, &mission) {
            epoch.advance();
        }
        let requested = epoch.0;
        let held = Arc::new(HeldModel {
            started: AtomicBool::new(false),
            release: AtomicBool::new(false),
            finished: AtomicBool::new(false),
        });
        let mut settings = config("ws://127.0.0.1:1", Provider::Ollama, SAFETY_NET_SECONDS);
        settings.decision_budget = Duration::from_secs(10);
        let (tx, rx) = oneshot::channel();
        let handle = spawn_decision(
            held.clone(),
            budget(0.0),
            Arc::new(tactical_questions()),
            Asker::from_config(&settings),
            serde_json::json!({}),
            Plan::default(),
            Gate::default(),
            0.0,
            tx,
        );
        assert!(
            wait_for(
                || held.started.load(Ordering::SeqCst),
                Duration::from_secs(10)
            )
            .await
        );
        for tick in 2..=20 {
            let before = mission.clone();
            mission.changed_at = tick;
            mission.party[0].aboard = tick % 2 == 0;
            let facts = mission.m05.as_mut().unwrap();
            facts.tram.tick = tick;
            facts.tram.feet[2] += 0.06;
            facts.tram.phase = if tick % 2 == 0 {
                M05TramPhase::Blocked
            } else {
                M05TramPhase::Moving
            };
            facts.captives[0].feet[2] += 0.01;
            if DecisionEpoch::mission_changed(Some(&before), &mission) {
                epoch.advance();
            }
        }
        held.release.store(true, Ordering::SeqCst);
        let (outcome, _) = tokio::time::timeout(Duration::from_secs(3), rx)
            .await
            .unwrap()
            .unwrap();
        handle.await.unwrap();
        assert!(
            matches!(outcome, Outcome::Decided(_)),
            "fake model returns a real parsed plan"
        );
        assert!(
            epoch.accepts(requested),
            "continuous physical facts preserve the delayed reply"
        );
        let before = mission.clone();
        mission.m05.as_mut().unwrap().current.as_mut().unwrap().id =
            "grenade_lesson_cleared".into();
        if DecisionEpoch::mission_changed(Some(&before), &mission) {
            epoch.advance();
        }
        assert!(
            !epoch.accepts(requested),
            "a new objective invalidates prior intent"
        );
        let retry_request = epoch.0;
        let before = mission.clone();
        mission.attempt += 1;
        if DecisionEpoch::mission_changed(Some(&before), &mission) {
            epoch.advance();
        }
        assert!(
            !epoch.accepts(retry_request),
            "retry invalidates even identical objective intent"
        );
        let before = mission.clone();
        mission.party[0].ready = false;
        assert!(
            DecisionEpoch::mission_changed(Some(&before), &mission),
            "readiness remains semantic"
        );
        let before = mission.clone();
        mission.m05.as_mut().unwrap().freight_open = true;
        assert!(
            DecisionEpoch::mission_changed(Some(&before), &mission),
            "world choice remains semantic"
        );
        let mut yard = mission.clone();
        yard.id = MissionId::ScheduledService;
        yard.m05 = None;
        yard.m03 = Some(fragr_server::protocol::M03ObjectiveState {
            mast_hp: 80,
            mast_secured: false,
            train_secured: false,
            current: None,
            cars: vec![fragr_server::protocol::M03CarState {
                id: "platform_car".into(),
                released: true,
                captives: [[0.0; 3]; 2],
            }],
        });
        let before = yard.clone();
        yard.m03.as_mut().unwrap().cars[0].captives[0][2] = 0.05;
        assert!(
            !DecisionEpoch::mission_changed(Some(&before), &yard),
            "walking car captives preserve intent"
        );
        yard.m03.as_mut().unwrap().cars[0].released = false;
        assert!(
            DecisionEpoch::mission_changed(Some(&before), &yard),
            "car release choice invalidates intent"
        );
        let mut town = mission;
        town.id = MissionId::NoticeToVacate;
        town.m05 = None;
        town.m04 = Some(fragr_server::protocol::M04ObjectiveState {
            completed: vec![],
            current: None,
            clinic_secured: true,
            clinic_open: true,
            patients_released: true,
            patients: vec![fragr_server::protocol::M04PatientState {
                id: "patient_a".into(),
                feet: [0.0; 3],
            }],
            photos_completed: 0,
            carried_recall_cars: vec![],
        });
        let before = town.clone();
        town.m04.as_mut().unwrap().patients[0].feet[2] = 0.05;
        assert!(
            !DecisionEpoch::mission_changed(Some(&before), &town),
            "walking clinic patients preserve intent"
        );
        town.m04.as_mut().unwrap().patients_released = false;
        assert!(
            DecisionEpoch::mission_changed(Some(&before), &town),
            "patient release choice invalidates intent"
        );
        let mut port = town;
        port.id = MissionId::PortOfEntry;
        port.m04 = None;
        port.m06 = Some(fragr_server::protocol::M06ObjectiveState {
            completed: vec![],
            current: None,
            prisoner_route_marked: false,
            carried_recall_cars: vec![],
            carried_patients: vec![],
            carried_photos: 0,
            carried_released_workers: vec![],
            carried_evacuated_workers: vec![],
        });
        let before = port.clone();
        port.changed_at += 1;
        assert!(
            !DecisionEpoch::mission_changed(Some(&before), &port),
            "presentation tick alone preserves lunar intent"
        );
        port.m06.as_mut().unwrap().prisoner_route_marked = true;
        assert!(
            DecisionEpoch::mission_changed(Some(&before), &port),
            "optional lunar route changes future intent"
        );
        let before = port.clone();
        port.m06
            .as_mut()
            .unwrap()
            .completed
            .push("freight_cleared".into());
        assert!(
            DecisionEpoch::mission_changed(Some(&before), &port),
            "lunar objective changes invalidate delayed plans"
        );
    }

    #[tokio::test]
    async fn delayed_model_keeps_healing_and_discards_its_answer_after_death() {
        use crate::telemetry::fixtures::pad;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        let transport = Arc::new(HeldModel {
            started: AtomicBool::new(false),
            release: AtomicBool::new(false),
            finished: AtomicBool::new(false),
        });
        let held = transport.clone();
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(socket).await.unwrap();
            ws.next().await.unwrap().unwrap(); // Hello.
            ws.next().await.unwrap().unwrap(); // Initial behavior.
            let id = Uuid::from_u128(1);
            let welcome = serde_json::json!({"type":"welcome", "player_id":id, "role":"agent"});
            let mut map =
                serde_json::to_value(fragr_server::sim::GameState::new().map_info()).unwrap();
            map["solids"] = serde_json::json!([]);
            map["presentation"] = serde_json::Value::Null;
            let mut scene = snapshot(
                1,
                vec![
                    player("Brain-1", id, 0.0, 0.0, 100, "flechette"),
                    player("Foe", Uuid::from_u128(2), 20.0, 0.0, 100, "rail"),
                ],
                vec![pad("health", "", -8.0, 0.0, true)],
            );
            for message in [
                welcome.to_string(),
                map.to_string(),
                serde_json::to_string(&ServerMessage::Snapshot(scene.clone())).unwrap(),
            ] {
                ws.send(Message::Text(message)).await.unwrap();
            }
            assert!(
                wait_for(
                    || held.started.load(Ordering::SeqCst),
                    Duration::from_secs(10)
                )
                .await,
                "wait for actual inference readiness"
            );
            scene.tick = 2;
            scene.players[0].hp = 25;
            ws.send(Message::Text(
                serde_json::to_string(&ServerMessage::Snapshot(scene.clone())).unwrap(),
            ))
            .await
            .unwrap();
            let healed = tokio::time::timeout(Duration::from_secs(3), async {
                while let Some(Ok(Message::Text(text))) = ws.next().await {
                    if let Ok(ClientMessage::Action(action)) = serde_json::from_str(&text) {
                        if action.forward
                            && action
                                .look_at
                                .as_ref()
                                .is_some_and(|aim| aim.x == Some(-8.0))
                        {
                            return true;
                        }
                    }
                }
                false
            })
            .await
            .unwrap();
            assert!(
                healed,
                "new low health routes to its pad while inference is held"
            );
            assert!(!held.finished.load(Ordering::SeqCst));
            scene.tick = 3;
            scene.players[0].hp = 0;
            scene.round_state = Some("Ended".into());
            ws.send(Message::Text(
                serde_json::to_string(&ServerMessage::Snapshot(scene)).unwrap(),
            ))
            .await
            .unwrap();
            // Observe controller output from the dead snapshot before allowing
            // the old answer to return. This separates setup and action timing.
            tokio::time::timeout(Duration::from_secs(3), async {
                while let Some(Ok(Message::Text(text))) = ws.next().await {
                    if let Ok(ClientMessage::Action(action)) = serde_json::from_str(&text) {
                        if !action.forward && !action.fire {
                            break;
                        }
                    }
                }
            })
            .await
            .unwrap();
            held.release.store(true, Ordering::SeqCst);
            assert!(
                wait_for(
                    || held.finished.load(Ordering::SeqCst),
                    Duration::from_secs(3)
                )
                .await
            );
            // Keep the socket open for two macro periods so the returned
            // result and the subsequent local cycle both run.
            tokio::time::sleep(Duration::from_millis(450)).await;
            ws.close(None).await.unwrap();
        });
        let mut settings = config(&url, Provider::Ollama, SAFETY_NET_SECONDS);
        settings.decision_budget = Duration::from_secs(10);
        let summary = run_bot(
            settings,
            transport,
            budget(0.0),
            Arc::new(AtomicBool::new(false)),
        )
        .await
        .unwrap();
        server.await.unwrap();
        assert_eq!(
            summary.decisions_remote, 0,
            "old reply cannot become live intent"
        );
        assert_eq!(summary.decisions_discarded, 1);
        assert_eq!(summary.decisions_failed, 0);
        assert!(summary.decisions_local >= 1);
        assert!(summary.actions_sent >= 2);
        assert_eq!(summary.run_usd, 0.0);
    }

    /// Poll a condition with a bounded, generous wait, sleeping briefly
    /// between checks. Live cadence tests synchronize on actual readiness
    /// (here, the transport having been reached) before timing the short,
    /// fixed decision-cadence window that follows, instead of folding
    /// unbounded connect-and-warmup latency into that same window.
    async fn wait_for(mut condition: impl FnMut() -> bool, bound: Duration) -> bool {
        let deadline = tokio::time::Instant::now() + bound;
        loop {
            if condition() {
                return true;
            }
            if tokio::time::Instant::now() >= deadline {
                return false;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    }

    #[tokio::test]
    async fn invalid_map_stops_before_actions_or_paid_decisions() {
        let valid = serde_json::to_value(fragr_server::sim::GameState::new().map_info()).unwrap();
        let mut extent = valid.clone();
        extent["half_extent"] = serde_json::json!(f32::MAX);
        let mut version = valid.clone();
        version["geometry_version"] = serde_json::json!("2");
        let mut solid = valid.clone();
        solid["solids"][0]["bottom"] = serde_json::json!("ceiling");
        let mut surfaces = valid.clone();
        surfaces["presentation"] = serde_json::json!({"ground":"concrete","solids":[]});
        let mut details = valid.clone();
        details["presentation"] = serde_json::json!({"ground":"concrete",
            "solids":vec!["enamel"; valid["solids"].as_array().unwrap().len()],
            "decorations":[{"solid":9999,"face":"north","center":[0,0],
                "size":[1,1],"kind":"terminal"}]});
        let rejected = serde_json::json!({"type": "error", "code": "unsupported_geometry", "message": "geometry version rejected"});
        for (bad, expected) in [
            (extent.to_string(), "invalid navigation map"),
            (version.to_string(), "invalid server message"),
            (solid.to_string(), "invalid server message"),
            (surfaces.to_string(), "invalid map presentation"),
            (details.to_string(), "invalid map presentation"),
            ("{broken".to_string(), "invalid server message"),
            (rejected.to_string(), "geometry version rejected"),
        ] {
            assert_bad_map_stops(valid.to_string(), bad, expected).await;
        }
    }

    async fn assert_bad_map_stops(valid: String, bad: String, expected: &str) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(socket).await.unwrap();
            let hello = ws.next().await.unwrap().unwrap();
            // The configured body travels in the same Hello every agent sends.
            assert!(matches!(
                serde_json::from_str::<ClientMessage>(hello.to_text().unwrap()).unwrap(),
                ClientMessage::Hello {
                    body: Some(fragr_server::protocol::BodyKind::Synthetic),
                    role: Role::Agent,
                    ..
                }
            ));
            ws.next().await.unwrap().unwrap(); // Initial stance.
            ws.send(Message::Text(valid)).await.unwrap();
            ws.send(Message::Text(bad)).await.unwrap();
            while let Some(Ok(message)) = ws.next().await {
                if let Message::Text(text) = message {
                    assert!(!matches!(
                        serde_json::from_str::<ClientMessage>(&text),
                        Ok(ClientMessage::Action(_))
                    ));
                }
            }
        });
        let transport = Arc::new(FakeTransport::ok(push_answers()));
        // The scripted server task below is only as fast as the executor
        // schedules it under contention; this run ends as soon as the bad
        // map arrives and is rejected, so a generous bound never slows the
        // common case, it only keeps the race off the assertion.
        let result = run_bot(
            config(&url, Provider::OpenRouter, SAFETY_NET_SECONDS),
            transport.clone(),
            budget(1.0),
            Arc::new(AtomicBool::new(false)),
        )
        .await;
        assert!(matches!(result, Err(Error::Transport(message)) if message.contains(expected)));
        assert_eq!(transport.calls(), 0);
        server.await.unwrap();
    }

    #[tokio::test]
    async fn a_bad_key_switches_the_brain_off_after_one_call() {
        let (url, shutdown) = boot_server(1).await;
        let transport = Arc::new(FakeTransport::new(vec![Ok(HttpResponse {
            status: 401,
            body: br#"{"error":{"message":"No auth"}}"#.to_vec(),
        })]));
        let budget = budget(1.0);
        let stop = Arc::new(AtomicBool::new(false));
        let handle = tokio::spawn(run_bot(
            config(&url, Provider::OpenRouter, SAFETY_NET_SECONDS),
            transport.clone(),
            budget.clone(),
            stop.clone(),
        ));
        // Connect and warmup are unbounded relative to the fixed decision
        // cadence under contention; synchronize on the one paid call actually
        // reaching the transport before timing the cadence-only window below.
        assert!(
            wait_for(|| transport.calls() >= 1, Duration::from_secs(10)).await,
            "the one paid call never reached the transport"
        );
        // Local rules take over immediately after the fatal failure; the
        // 200ms macro cadence needs two more cycles (400ms), so this bounded
        // margin is generous even under contention.
        tokio::time::sleep(Duration::from_millis(1_500)).await;
        stop.store(true, Ordering::Relaxed);
        let summary = handle.await.unwrap().expect("bot runs");
        assert_eq!(summary.decisions_failed, 1, "{summary:?}");
        assert_eq!(summary.fatal_failures, 1);
        assert_eq!(transport.calls(), 1, "no phantom charges after a 401");
        assert!(summary.brain_disabled.as_deref().unwrap().contains("401"));
        assert!(
            summary.decisions_local >= 2,
            "local rules take over: {summary:?}"
        );
        assert_eq!(budget.lock().unwrap().run_calls(), 1);
        let _ = shutdown.send(());
    }

    #[tokio::test]
    async fn unreadable_answer_blocks_further_paid_calls() {
        let (url, shutdown) = boot_server(1).await;
        let transport = Arc::new(FakeTransport::new(vec![Ok(HttpResponse {
            status: 200,
            body: b"not json".to_vec(),
        })]));
        let stop = Arc::new(AtomicBool::new(false));
        let handle = tokio::spawn(run_bot(
            config(&url, Provider::Typesafe, SAFETY_NET_SECONDS),
            transport.clone(),
            budget(1.0),
            stop.clone(),
        ));
        assert!(
            wait_for(|| transport.calls() >= 1, Duration::from_secs(10)).await,
            "the one unreadable call never reached the transport"
        );
        // A malformed reply neither backs off nor disables the brain by
        // itself; the second, budget-pending cycle needs one more 200ms
        // macro tick, so this bounded margin is generous even under load.
        tokio::time::sleep(Duration::from_millis(1_500)).await;
        stop.store(true, Ordering::Relaxed);
        let summary = handle.await.unwrap().expect("bot runs");
        assert_eq!(transport.calls(), 1, "{summary:?}");
        assert_eq!(summary.decisions_failed, 1);
        assert_eq!(summary.budget_refusals, 1);
        assert_eq!(summary.fatal_failures, 0);
        assert!(summary.brain_disabled.is_some());
        let _ = shutdown.send(());
    }

    #[test]
    fn brain_is_only_asked_while_alive_and_active() {
        use crate::telemetry::fixtures::{player, snapshot};
        let me = Uuid::new_v4();
        let mut hits = RecentHits::default();
        let alive = snapshot(1, vec![player("me", me, 0.0, 0.0, 50, "rail")], vec![]);
        assert!(brain_worth_asking(&observe(me, &alive, &mut hits).unwrap()));
        let dead = snapshot(1, vec![player("me", me, 0.0, 0.0, 0, "rail")], vec![]);
        assert!(!brain_worth_asking(&observe(me, &dead, &mut hits).unwrap()));
        let mut warmup = alive.clone();
        warmup.round_state = Some("Warmup".to_string());
        assert!(!brain_worth_asking(
            &observe(me, &warmup, &mut hits).unwrap()
        ));
        let mut ended = alive.clone();
        ended.round_state = Some("Ended".to_string());
        assert!(!brain_worth_asking(
            &observe(me, &ended, &mut hits).unwrap()
        ));
        assert!(is_fatal(&Error::Api {
            status: 401,
            message: String::new()
        }));
        assert!(is_fatal(&Error::Api {
            status: 400,
            message: String::new()
        }));
        assert!(!is_fatal(&Error::Api {
            status: 503,
            message: String::new()
        }));
        assert!(!is_fatal(&Error::Malformed(String::new())));
    }

    #[test]
    fn backoff_doubles_and_caps() {
        let base = Duration::from_millis(200);
        assert_eq!(backoff_interval(base, 0), base);
        assert_eq!(backoff_interval(base, 1), Duration::from_millis(400));
        assert_eq!(backoff_interval(base, 4), Duration::from_millis(3200));
        assert_eq!(backoff_interval(base, 9), Duration::from_millis(3200));
        assert!(is_retryable(&Error::Transport("timeout".into())));
        assert!(is_retryable(&Error::Api {
            status: 429,
            message: String::new()
        }));
        assert!(is_retryable(&Error::Api {
            status: 529,
            message: String::new()
        }));
        assert!(!is_retryable(&Error::Api {
            status: 401,
            message: String::new()
        }));
        assert!(!is_retryable(&Error::Malformed(String::new())));
    }

    #[test]
    fn latency_stats_track_min_max_mean() {
        let mut stats = LatencyStats::default();
        assert_eq!(stats.samples, 0);
        stats.push(400);
        stats.push(200);
        stats.push(600);
        assert_eq!(stats.samples, 3);
        assert_eq!(stats.min_ms, 200);
        assert_eq!(stats.max_ms, 600);
        assert!((stats.mean_ms - 400.0).abs() < 1e-9);
    }

    #[tokio::test]
    async fn local_provider_plays_for_free() {
        let (url, shutdown) = boot_server(2).await;
        let transport = Arc::new(FakeTransport::ok(push_answers()));
        let stop = Arc::new(AtomicBool::new(false));
        // Local never touches the transport, so there is no external signal
        // to synchronize on; a generous window keeps the minimum snapshot,
        // action, and decision counts below reachable under contention
        // without folding connect-and-warmup latency into a tight budget.
        let summary = run_bot(
            config(&url, Provider::Local, 8),
            transport.clone(),
            budget(0.0),
            stop,
        )
        .await
        .expect("bot runs");
        assert!(summary.snapshots > 10, "{summary:?}");
        assert!(summary.actions_sent > 10, "{summary:?}");
        assert!(summary.decisions_local >= 3, "{summary:?}");
        assert_eq!(summary.decisions_remote, 0);
        assert_eq!(transport.calls(), 0, "local never touches the transport");
        assert_eq!(summary.run_usd, 0.0);
        assert_eq!(summary.provider, "local");
        assert!(
            summary.kills.is_some(),
            "live server sends a participant record"
        );
        assert!(
            summary.player_id.is_some(),
            "admitted brain has an identity"
        );
        assert_eq!(summary.last_plan.as_ref().unwrap().source, Source::Local);
        assert!(summary.last_state.as_ref().unwrap().starts_with("SELF hp="));
        let _ = shutdown.send(());
    }

    #[tokio::test]
    async fn six_free_brains_play_ctf_on_real_sockets() {
        use fragr_server::protocol::{GameMode, Team};
        let (url, shutdown) = boot_server_with_mode(0, GameMode::Ctf).await;
        let transport = Arc::new(FakeTransport::ok(push_answers()));
        let stop = Arc::new(AtomicBool::new(false));
        let (mut observer, _) = connect_async(&url).await.unwrap();
        let hello = serde_json::json!({"type":"hello", "role":"spectator", "name":"Roster observer",
            "geometry_version":fragr_server::protocol::GEOMETRY_VERSION,
            "gameplay_version":fragr_server::protocol::GAMEPLAY_VERSION});
        observer
            .send(Message::Text(hello.to_string()))
            .await
            .unwrap();
        let mut handles = Vec::new();
        for index in 1..=6 {
            let mut settings = config(&url, Provider::Local, SAFETY_NET_SECONDS);
            settings.name = format!("Roster-{index}");
            handles.push(tokio::spawn(run_bot(
                settings,
                transport.clone(),
                budget(0.0),
                stop.clone(),
            )));
        }
        let first_tick = tokio::time::timeout(Duration::from_secs(10), async {
            while let Some(Ok(Message::Text(text))) = observer.next().await {
                if let Ok(ServerMessage::Snapshot(snapshot)) = serde_json::from_str(&text) {
                    if snapshot.players.len() == 6
                        && snapshot
                            .players
                            .iter()
                            .all(|p| p.behavior.as_deref().and_then(Stance::parse).is_some())
                    {
                        assert!(
                            snapshot.flags.is_some(),
                            "authoritative CTF flag state replicated"
                        );
                        for team in Team::ALL {
                            assert_eq!(
                                snapshot
                                    .players
                                    .iter()
                                    .filter(|p| p.team == Some(team))
                                    .count(),
                                3
                            );
                        }
                        return snapshot.tick;
                    }
                }
            }
            panic!("observer ended before roster readiness")
        })
        .await
        .expect("six compatible controllers become ready");
        tokio::time::timeout(Duration::from_secs(5), async {
            while let Some(Ok(Message::Text(text))) = observer.next().await {
                if let Ok(ServerMessage::Snapshot(snapshot)) = serde_json::from_str(&text) {
                    if snapshot.tick >= first_tick + 40 {
                        return;
                    }
                }
            }
            panic!("observer ended before the action window")
        })
        .await
        .expect("forty actual server ticks elapse after roster readiness");
        stop.store(true, Ordering::Relaxed);
        let mut receipts = Vec::new();
        for handle in handles {
            let summary = handle.await.unwrap().unwrap();
            assert!(
                summary.snapshots >= 10 && summary.actions_sent >= 10,
                "{summary:?}"
            );
            assert_eq!(summary.provider, "local");
            assert_eq!(summary.run_usd, 0.0);
            assert_eq!(summary.decisions_remote, 0);
            receipts.push(summary);
        }
        assert_eq!(transport.calls(), 0, "no model provider called");
        println!(
            "CTF_SOCKET_SMOKE {}",
            serde_json::to_string(&receipts).unwrap()
        );
        let _ = observer.close(None).await;
        let _ = shutdown.send(());
    }

    #[tokio::test]
    async fn remote_answers_drive_the_plan_and_the_ledger() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        // The static healthy far-target fallback is HoldAngle, so every
        // observed stance below proves model adoption rather than a local cycle.
        let expected = [
            Stance::PushEnemy,
            Stance::KiteDistance,
            Stance::FallBackHeal,
        ];
        let transport = Arc::new(FakeTransport::new(
            expected
                .iter()
                .map(|stance| {
                    let mut reply = push_answers();
                    reply["answers"]["stance"]["choice"] = stance.name().into();
                    reply["answers"]["stance"]["probabilities"] =
                        serde_json::json!({stance.name(): 0.91});
                    Ok(HttpResponse {
                        status: 200,
                        body: reply.to_string().into_bytes(),
                    })
                })
                .collect(),
        ));
        let budget = budget(1.0);
        let stop = Arc::new(AtomicBool::new(false));
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let mut socket = tokio_tungstenite::accept_async(socket).await.unwrap();
            socket.next().await.unwrap().unwrap(); // Hello.
            socket.next().await.unwrap().unwrap(); // Initial stance before observations.
            let id = Uuid::from_u128(1);
            let mut map =
                serde_json::to_value(fragr_server::sim::GameState::new().map_info()).unwrap();
            map["solids"] = serde_json::json!([]);
            map["presentation"] = serde_json::Value::Null;
            let scene = snapshot(
                1,
                vec![
                    player("Brain-1", id, 0.0, 0.0, 100, "rail"),
                    player("Foe", Uuid::from_u128(2), 35.0, 0.0, 100, "rail"),
                ],
                vec![],
            );
            for wire in [
                serde_json::json!({"type":"welcome", "player_id":id, "role":"agent"}).to_string(),
                map.to_string(),
                serde_json::to_string(&ServerMessage::Snapshot(scene)).unwrap(),
            ] {
                socket.send(Message::Text(wire)).await.unwrap();
            }
            let adopted = tokio::time::timeout(Duration::from_secs(10), async {
                let mut adopted = Vec::new();
                while let Some(Ok(Message::Text(wire))) = socket.next().await {
                    if let Ok(ClientMessage::SetDisplayBehavior(behavior)) =
                        serde_json::from_str(&wire)
                    {
                        let stance = Stance::parse(&behavior.behavior).unwrap();
                        if stance == expected[adopted.len()] {
                            adopted.push(stance);
                            if adopted.len() == expected.len() {
                                break;
                            }
                        }
                    }
                }
                adopted
            })
            .await
            .expect("three remote stances publish after actual readiness");
            socket.close(None).await.unwrap();
            adopted
        });
        let handle = tokio::spawn(run_bot(
            config(&url, Provider::Typesafe, SAFETY_NET_SECONDS),
            transport.clone(),
            budget.clone(),
            stop.clone(),
        ));
        assert_eq!(
            server.await.unwrap(),
            expected,
            "every scripted remote plan is adopted on the real action session"
        );
        let summary = handle.await.unwrap().expect("bot runs");
        assert!(summary.decisions_remote >= 3, "{summary:?}");
        assert_eq!(summary.budget_refusals, 0);
        assert_eq!(summary.decisions_failed, 0);
        assert_eq!(summary.decisions_discarded, 0);
        assert_eq!(summary.decisions_low_confidence, 0);
        assert!(transport.calls() >= 3);
        assert!(summary.run_usd > 0.0);
        {
            let ledger = budget.lock().unwrap();
            assert_eq!(ledger.run_calls() as usize, transport.calls());
            assert_eq!(ledger.ledger().charges.len(), transport.calls());
            assert!(ledger
                .ledger()
                .charges
                .iter()
                .all(|charge| charge.ok && charge.settled));
            assert_eq!(
                summary.run_usd,
                ledger
                    .ledger()
                    .charges
                    .iter()
                    .map(crate::budget::Charge::billed_usd)
                    .sum::<f64>()
            );
            assert!(summary.decisions_remote <= ledger.run_calls());
            assert!(
                ledger.run_calls() - summary.decisions_remote <= 1,
                "only the single draining flight may settle without adoption"
            );
        }
        assert!(summary.decision_latency.samples >= 3);
        assert!(summary.decision_latency.max_ms >= summary.decision_latency.min_ms);
        let sent = transport.last_request.lock().unwrap().clone().unwrap();
        let state = sent.body.unwrap()["state"].clone();
        assert!(state.is_object(), "the brain gets an object: {state}");
        assert!(state["self"]["health"].is_string());
    }

    /// What Ollama returns for one scoring call: letter A, far ahead of the rest.
    fn letter_a() -> serde_json::Value {
        let top: Vec<serde_json::Value> = [
            ("A", -0.01),
            ("B", -5.0),
            ("C", -6.0),
            ("D", -7.0),
            ("E", -8.0),
        ]
        .iter()
        .map(|(token, logprob)| serde_json::json!({"token": token, "logprob": logprob}))
        .collect();
        serde_json::json!({
            "response": "A",
            "done": true,
            "logprobs": [{"token": "A", "logprob": -0.01, "top_logprobs": top}]
        })
    }

    /// Answers every request after a fixed delay.
    struct Slow {
        delay: Duration,
        reply: HttpResponse,
        calls: std::sync::atomic::AtomicUsize,
    }

    impl Transport for Slow {
        fn send(&self, request: &crate::provider::HttpRequest) -> Result<HttpResponse, Error> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            let wait = request.timeout.map_or(self.delay, |t| t.min(self.delay));
            std::thread::sleep(wait);
            if wait < self.delay {
                return Err(Error::Timeout("request timed out".into()));
            }
            Ok(self.reply.clone())
        }
    }

    #[tokio::test]
    async fn a_local_model_decides_without_touching_the_budget() {
        let (url, shutdown) = boot_server(2).await;
        let transport = Arc::new(FakeTransport::ok(letter_a()));
        let budget = budget(0.0);
        let stop = Arc::new(AtomicBool::new(false));
        let handle = tokio::spawn(run_bot(
            config(&url, Provider::Ollama, SAFETY_NET_SECONDS),
            transport.clone(),
            budget.clone(),
            stop.clone(),
        ));
        // One stance request makes one play decision; wait for two decisions.
        assert!(
            wait_for(|| transport.calls() >= 2, Duration::from_secs(10)).await,
            "the local model was never asked twice"
        );
        stop.store(true, Ordering::Relaxed);
        let summary = handle.await.unwrap().expect("bot runs");
        assert_eq!(summary.provider, "ollama");
        assert!(summary.decisions_remote >= 1, "{summary:?}");
        assert_eq!(summary.budget_refusals, 0);
        assert_eq!(summary.run_usd, 0.0);
        assert_eq!(budget.lock().unwrap().run_calls(), 0, "no ledger entry");
        assert!(budget.lock().unwrap().ledger().charges.is_empty());
        let plan = summary.last_plan.as_ref().unwrap();
        assert_eq!(plan.source, Source::Remote);
        // Letter A is the first option in sorted order.
        assert_eq!(plan.stance, crate::plan::Stance::FallBackHeal);
        assert!(summary.decision_latency.samples >= 1);
        assert!(summary.decision_latency.p95_ms >= summary.decision_latency.p50_ms);
        assert!(summary.elapsed_seconds > 0.0);
        assert!(summary.decisions_per_second > 0.0);
        let sent = transport.last_request.lock().unwrap().clone().unwrap();
        let prompt = sent.body.as_ref().unwrap()["prompt"].as_str().unwrap();
        assert!(prompt.contains("Pick the stance"));
        assert!(!prompt.contains("Pick the weapon"));
        assert!(!prompt.contains("How close is this fighter"));
        assert!(sent.url.starts_with("http://127.0.0.1:11434/api/generate"));
        assert!(sent.headers.iter().all(|(name, _)| name != "Authorization"));
        let _ = shutdown.send(());
    }

    #[tokio::test]
    async fn a_slow_local_model_falls_back_and_backs_off() {
        let (url, shutdown) = boot_server(1).await;
        let transport = Arc::new(Slow {
            delay: Duration::from_millis(400),
            reply: HttpResponse {
                status: 200,
                body: letter_a().to_string().into_bytes(),
            },
            calls: std::sync::atomic::AtomicUsize::new(0),
        });
        let mut slow = config(&url, Provider::Ollama, SAFETY_NET_SECONDS);
        slow.decision_budget = Duration::from_millis(100);
        let stop = Arc::new(AtomicBool::new(false));
        let handle = tokio::spawn(run_bot(slow, transport.clone(), budget(0.0), stop.clone()));
        assert!(
            wait_for(
                || transport.calls.load(Ordering::SeqCst) >= 1,
                Duration::from_secs(10)
            )
            .await,
            "the slow model was never asked"
        );
        tokio::time::sleep(Duration::from_millis(600)).await;
        stop.store(true, Ordering::Relaxed);
        let summary = handle.await.unwrap().expect("bot runs");
        assert!(summary.timeouts >= 1, "{summary:?}");
        assert_eq!(summary.decisions_remote, 0);
        assert!(summary.fallbacks >= summary.timeouts);
        assert!(summary.backoffs >= 1, "a timeout slows the cadence");
        assert!(summary.brain_disabled.is_none());
        assert!(
            summary.decision_latency.max_ms < 400,
            "the budget cuts the wait"
        );
        let _ = shutdown.send(());
    }

    #[tokio::test]
    async fn unreadable_local_answers_switch_the_model_off() {
        let (url, shutdown) = boot_server(1).await;
        let transport = Arc::new(FakeTransport::new(vec![Ok(HttpResponse {
            status: 200,
            body: br#"{"response":"The","logprobs":[{"token":"The","logprob":-0.1,"top_logprobs":[]}]}"#
                .to_vec(),
        })]));
        let stop = Arc::new(AtomicBool::new(false));
        let handle = tokio::spawn(run_bot(
            config(&url, Provider::Ollama, SAFETY_NET_SECONDS),
            transport.clone(),
            budget(0.0),
            stop.clone(),
        ));
        assert!(
            wait_for(|| transport.calls() >= 3, Duration::from_secs(10)).await,
            "three unreadable answers never arrived"
        );
        tokio::time::sleep(Duration::from_millis(600)).await;
        stop.store(true, Ordering::Relaxed);
        let summary = handle.await.unwrap().expect("bot runs");
        assert_eq!(transport.calls(), MAX_CONSECUTIVE_MALFORMED as usize);
        assert_eq!(
            summary.decisions_failed,
            u64::from(MAX_CONSECUTIVE_MALFORMED)
        );
        assert_eq!(summary.fatal_failures, 1);
        assert!(summary.brain_disabled.is_some());
        assert!(summary.decisions_local >= 1, "{summary:?}");
        assert_eq!(summary.last_plan.as_ref().unwrap().source, Source::Failure);
        let _ = shutdown.send(());
    }

    #[tokio::test]
    async fn a_local_model_needs_a_checked_url_and_a_budget() {
        let transport = Arc::new(FakeTransport::ok(letter_a()));
        let mut no_url = config("ws://127.0.0.1:9", Provider::OpenJev, 1);
        no_url.model_url = None;
        let err = run_bot(
            no_url,
            transport.clone(),
            budget(0.0),
            Arc::new(AtomicBool::new(false)),
        )
        .await
        .unwrap_err();
        assert!(matches!(err, Error::InvalidArgument(_)), "{err}");
        let mut no_budget = config("ws://127.0.0.1:9", Provider::Ollama, 1);
        no_budget.decision_budget = Duration::ZERO;
        assert!(matches!(
            run_bot(
                no_budget,
                transport.clone(),
                budget(0.0),
                Arc::new(AtomicBool::new(false))
            )
            .await,
            Err(Error::InvalidArgument(_))
        ));
        assert_eq!(transport.calls(), 0);
    }

    #[test]
    fn percentiles_use_the_nearest_rank() {
        assert_eq!(percentile(&[], 50.0), 0);
        let sorted: Vec<u64> = (1..=20).collect();
        assert_eq!(percentile(&sorted, 50.0), 10);
        assert_eq!(percentile(&sorted, 95.0), 19);
        assert_eq!(percentile(&sorted, 0.0), 1);
        assert_eq!(percentile(&[7], 95.0), 7);
        let mut stats = LatencyStats::default();
        for ms in [300, 100, 200] {
            stats.push(ms);
        }
        stats.finish();
        assert_eq!((stats.p50_ms, stats.p95_ms), (200, 300));
        let shown = serde_json::to_value(&stats).unwrap();
        assert!(shown.get("retained").is_none());
        assert_eq!(shown["p95_ms"], 300);
    }

    #[tokio::test]
    async fn budget_refusal_switches_to_local_rules_once() {
        let (url, shutdown) = boot_server(1).await;
        let transport = Arc::new(FakeTransport::ok(push_answers()));
        let stop = Arc::new(AtomicBool::new(false));
        // The refusal is an immediate, in-memory cap check that never reaches
        // the transport, so there is no external signal to synchronize on; a
        // generous window keeps the minimum local-decision count reachable
        // under contention without folding setup latency into a tight budget.
        let summary = run_bot(
            config(&url, Provider::OpenRouter, 8),
            transport.clone(),
            budget(0.0),
            stop,
        )
        .await
        .expect("bot runs");
        assert_eq!(summary.budget_refusals, 1, "{summary:?}");
        assert!(summary.decisions_local >= 2, "local rules take over");
        assert_eq!(transport.calls(), 0, "nothing is sent without a cap");
        assert_eq!(summary.last_plan.as_ref().unwrap().source, Source::Budget);
        assert_eq!(summary.run_usd, 0.0);
        let _ = shutdown.send(());
    }

    #[tokio::test]
    async fn failed_calls_fall_back_and_still_count() {
        let (url, shutdown) = boot_server(1).await;
        let transport = Arc::new(FakeTransport::new(vec![Ok(HttpResponse {
            status: 503,
            body: br#"{"error":{"message":"overloaded"}}"#.to_vec(),
        })]));
        let budget = budget(1.0);
        let stop = Arc::new(AtomicBool::new(false));
        let handle = tokio::spawn(run_bot(
            config(&url, Provider::Typesafe, SAFETY_NET_SECONDS),
            transport.clone(),
            budget.clone(),
            stop.clone(),
        ));
        // Connect and warmup are unbounded relative to the fixed decision
        // cadence under contention; synchronize on the one retryable call
        // actually reaching the transport before timing the cadence-only
        // window below.
        assert!(
            wait_for(|| transport.calls() >= 1, Duration::from_secs(10)).await,
            "the one retryable call never reached the transport"
        );
        // The backoff after one retryable failure doubles the 200ms cadence
        // to 400ms before the budget-pending second cycle; this bounded
        // margin is generous even under contention.
        tokio::time::sleep(Duration::from_millis(1_500)).await;
        stop.store(true, Ordering::Relaxed);
        let summary = handle.await.unwrap().expect("bot runs");
        assert_eq!(summary.decisions_failed, 1, "{summary:?}");
        assert_eq!(summary.decisions_remote, 0);
        assert_eq!(summary.last_plan.as_ref().unwrap().source, Source::Budget);
        assert!(
            summary.backoffs >= 1,
            "a 503 slows the cadence: {summary:?}"
        );
        assert_eq!(summary.budget_refusals, 1);
        assert_eq!(transport.calls(), 1);
        assert_eq!(summary.fatal_failures, 0);
        assert!(summary.brain_disabled.is_some());
        assert!(
            summary.run_usd > 0.0,
            "sent calls are charged at the estimate"
        );
        let _ = shutdown.send(());
    }

    #[tokio::test]
    async fn stop_flag_and_missing_key_and_bad_url() {
        let (url, shutdown) = boot_server(0).await;
        let transport = Arc::new(FakeTransport::ok(push_answers()));
        let stop = Arc::new(AtomicBool::new(true));
        let summary = run_bot(
            config(&url, Provider::Local, 30),
            transport.clone(),
            budget(0.0),
            stop,
        )
        .await
        .expect("bot exits on stop");
        assert_eq!(summary.actions_sent, 0);
        let mut no_key = config(&url, Provider::Typesafe, 1);
        no_key.api_key = None;
        assert!(matches!(
            run_bot(
                no_key,
                transport.clone(),
                budget(1.0),
                Arc::new(AtomicBool::new(false))
            )
            .await,
            Err(Error::MissingApiKey(_))
        ));
        // A port nobody listens on: bind, learn the number, release it.
        let free = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = free.local_addr().unwrap().port();
        drop(free);
        let bad = config(&format!("ws://127.0.0.1:{port}"), Provider::Local, 1);
        let started = std::time::Instant::now();
        assert!(matches!(
            run_bot(
                bad,
                transport,
                budget(0.0),
                Arc::new(AtomicBool::new(false))
            )
            .await,
            Err(Error::Transport(_))
        ));
        assert!(started.elapsed() < CONNECT_TIMEOUT + Duration::from_secs(1));
        let _ = shutdown.send(());
        let _ = Refusal::NoCap;
    }

    #[test]
    fn display_behavior_wire_only_on_stance_change() {
        let mut published = None;
        let first = display_behavior_wire(&mut published, Stance::HoldAngle).unwrap();
        assert!(first.contains("set_display_behavior"));
        assert!(first.contains("hold_angle"));
        assert!(display_behavior_wire(&mut published, Stance::HoldAngle).is_none());
        let next = display_behavior_wire(&mut published, Stance::PushEnemy).unwrap();
        assert!(next.contains("push_enemy"));
        assert_eq!(published, Some(Stance::PushEnemy));
    }

    #[tokio::test]
    async fn brain_publishes_stance_chip_on_join() {
        let (url, shutdown) = boot_server(0).await;
        let transport = Arc::new(FakeTransport::ok(push_answers()));
        let stop = Arc::new(AtomicBool::new(false));
        // The spectator below synchronizes on actual readiness (the stance
        // chip) and drives the bot's end through `stop`; run_bot's own
        // deadline is only a safety net, so it must outlast that wait
        // instead of racing connect-and-warmup latency against it.
        let bot = tokio::spawn(run_bot(
            config(&url, Provider::Local, SAFETY_NET_SECONDS),
            transport,
            budget(0.0),
            stop.clone(),
        ));
        // Spectator reads snapshots until Brain-1 shows a stance chip.
        let (ws, _) = connect_async(&url).await.expect("spec connect");
        let (mut sink, mut stream) = ws.split();
        sink.send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                body: None,
                gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
                geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
                role: Role::Spectator,
                name: "Spec".into(),

                ticket: None,
                resume: None,
            })
            .unwrap(),
        ))
        .await
        .unwrap();
        let mut saw = false;
        let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
        while tokio::time::Instant::now() < deadline {
            let Some(Ok(Message::Text(text))) = stream.next().await else {
                break;
            };
            let Ok(ServerMessage::Snapshot(snap)) = serde_json::from_str(&text) else {
                continue;
            };
            if let Some(p) = snap.players.iter().find(|p| p.name == "Brain-1") {
                if p.behavior.as_deref() == Some("hold_angle")
                    || p.behavior.as_deref() == Some("push_enemy")
                    || p.behavior.as_deref() == Some("fall_back_heal")
                    || p.behavior.as_deref() == Some("kite_distance")
                {
                    saw = true;
                    break;
                }
            }
        }
        stop.store(true, Ordering::Relaxed);
        let _ = bot.await;
        let _ = shutdown.send(());
        assert!(saw, "spectator never saw Brain-1 stance chip");
    }
}

#[cfg(test)]
mod stream_tests {
    use super::*;

    #[test]
    fn a_fighter_stream_is_in_range_and_reproduces() {
        let mut a = seed_from_name("Static Kid");
        let mut b = seed_from_name("Static Kid");
        for _ in 0..200 {
            let x = next_roll(&mut a);
            assert!((0.0..1.0).contains(&x), "roll out of range: {x}");
            assert_eq!(
                x,
                next_roll(&mut b),
                "the same name must replay the same run"
            );
        }
    }

    #[test]
    fn two_fighters_do_not_move_in_lockstep() {
        let mut a = seed_from_name("Static Kid");
        let mut b = seed_from_name("Aunt Linda");
        let mut same = 0;
        for _ in 0..100 {
            if next_roll(&mut a) == next_roll(&mut b) {
                same += 1;
            }
        }
        assert_eq!(same, 0, "two names drew the same sequence");
    }

    #[test]
    fn an_empty_name_still_gives_a_working_stream() {
        // xorshift is stuck at zero forever, so the seed must never be zero.
        let mut state = seed_from_name("");
        assert_ne!(state, 0);
        let first = next_roll(&mut state);
        assert!((0.0..1.0).contains(&first));
        assert_ne!(first, next_roll(&mut state));
    }

    #[test]
    fn the_draw_spreads_across_the_range() {
        let mut state = seed_from_name("spread");
        let mut buckets = [0usize; 4];
        for _ in 0..4000 {
            let x = next_roll(&mut state);
            buckets[(x * 4.0) as usize % 4] += 1;
        }
        for (i, count) in buckets.iter().enumerate() {
            assert!(
                *count > 800 && *count < 1200,
                "quarter {i} got {count} of 4000"
            );
        }
    }

    #[test]
    fn memory_collapses_a_run_and_keeps_the_newest() {
        let mut memory = std::collections::VecDeque::new();
        for decision in ["push", "push", "push", "hold", "push", "hold", "push"] {
            remember(&mut memory, decision);
        }
        assert_eq!(
            memory.iter().cloned().collect::<Vec<_>>(),
            vec!["hold", "push", "hold", "push"],
            "an oscillation must survive in the window, a long hold must not fill it"
        );
    }
}
