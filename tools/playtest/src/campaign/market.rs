//! Observer-only market boundaries. Entry means the public market objective
//! began, not that its actors spawned or first took damage. Challenge flags
//! are monotone over an attempt; only their first observed transition after
//! this boundary has stage timing, and even that does not identify an owner.
use fragr_server::protocol::{CampaignRunStatus, LoadoutState, MissionState};
use serde::{Deserialize, Serialize};

pub(super) mod stage;
#[cfg(test)]
mod tests;

#[derive(Debug, Default, Clone, Serialize, Deserialize, PartialEq)]
pub struct Metrics {
    pub attempts: Vec<Attempt>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Attempt {
    pub attempt: u32,
    pub entered_market: bool,
    pub outcome: Outcome,
    pub receipts: Vec<Receipt>,
    pub interruption: Attribution,
    pub strip_damage: Attribution,
    /// Per-action market facts after public market entry. Absent before entry.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stage: Option<stage::Facts>,
    /// Per-action facts on the continuation after market completion, only
    /// when the survey runs through the water tanks. Absent otherwise.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<stage::Facts>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    InProgress,
    Complete,
    Death,
    Exhausted,
    Timeout,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Attribution {
    /// No stage-attributable transition. This is not evidence of no hit.
    Unknown,
    /// A public flag first changed after market entry. Timing only, not a
    /// particular Paver, exclusive cause, or number of events.
    FirstObservedDuringMarket,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Event {
    Entry,
    MarketEntry,
    MarketComplete,
    /// The next authored objective, `water_tanks`, completed with the body alive.
    TanksComplete,
    Death,
    Exhausted,
    Timeout,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Receipt {
    pub event: Event,
    pub tick: u64,
    pub current_objective: Option<String>,
    pub continues: Option<u8>,
    /// Missing participant/equipment facts stay unknown, never fabricated.
    pub status: Option<Status>,
    pub attempt_paver_interrupted: bool,
    pub attempt_strip_struck: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Status {
    pub feet: [f32; 3],
    pub hp: i32,
    pub armor: i32,
    /// Ammo pools already include loaded magazine rounds. Do not add them.
    pub loadout: LoadoutState,
}

#[derive(Default)]
pub(super) struct Recorder {
    metrics: Metrics,
    previous_flags: [bool; 2],
    tracker: stage::Tracker,
    /// Continue past market completion to the water tanks arrival.
    through_tanks: bool,
}

impl Recorder {
    /// A recorder whose completion is the water tanks arrival. The market
    /// completion receipt stays as a non-terminal boundary.
    pub(super) fn through_tanks() -> Self {
        Self {
            through_tanks: true,
            ..Self::default()
        }
    }

    pub(super) fn observe(&mut self, tick: u64, state: &MissionState, status: Option<Status>) {
        let Some(facts) = &state.m19 else {
            return;
        };
        let flags = [
            facts.challenges.paver_interrupted,
            facts.challenges.strip_struck,
        ];
        if self
            .metrics
            .attempts
            .last()
            .is_none_or(|row| row.attempt != state.attempt)
        {
            self.metrics.attempts.push(Attempt {
                attempt: state.attempt,
                entered_market: false,
                outcome: Outcome::InProgress,
                receipts: vec![receipt(Event::Entry, tick, state, status.clone())],
                interruption: Attribution::Unknown,
                strip_damage: Attribution::Unknown,
                stage: None,
                continuation: None,
            });
            self.previous_flags = flags;
            self.tracker.reset();
        }
        let row = self.metrics.attempts.last_mut().expect("attempt inserted");
        if row.outcome != Outcome::InProgress {
            return;
        }
        if row.continuation.is_some() {
            // After market completion a new flag is not market timing.
        } else if row.entered_market {
            if !self.previous_flags[0] && flags[0] {
                row.interruption = Attribution::FirstObservedDuringMarket;
            }
            if !self.previous_flags[1] && flags[1] {
                row.strip_damage = Attribution::FirstObservedDuringMarket;
            }
        } else if facts.completed.iter().any(|id| id == "tram_street") {
            row.entered_market = true;
            row.stage = Some(stage::Facts {
                entry_ranged_rounds: status
                    .as_ref()
                    .map_or(0, |status| stage::ranged_rounds(&status.loadout)),
                ..Default::default()
            });
            row.receipts
                .push(receipt(Event::MarketEntry, tick, state, status.clone()));
        }
        self.previous_flags = flags;
        let run_status = state.run.map(|run| run.status);
        let terminal = if run_status == Some(CampaignRunStatus::Failed) {
            Some((Outcome::Exhausted, Event::Exhausted))
        } else if run_status == Some(CampaignRunStatus::Continue)
            || status.as_ref().is_some_and(|status| status.hp <= 0)
        {
            Some((Outcome::Death, Event::Death))
        } else if status.as_ref().is_some_and(|status| status.hp > 0)
            && facts.completed.iter().any(|id| id == "market_strips")
        {
            if !self.through_tanks {
                Some((Outcome::Complete, Event::MarketComplete))
            } else {
                if row.continuation.is_none() {
                    row.receipts
                        .push(receipt(Event::MarketComplete, tick, state, status.clone()));
                    row.continuation = Some(stage::Facts {
                        entry_ranged_rounds: status
                            .as_ref()
                            .map_or(0, |status| stage::ranged_rounds(&status.loadout)),
                        ..Default::default()
                    });
                    if let Some(market) = row.stage.as_mut() {
                        self.tracker.close(market, tick);
                    }
                }
                facts
                    .completed
                    .iter()
                    .any(|id| id == "water_tanks")
                    .then_some((Outcome::Complete, Event::TanksComplete))
            }
        } else {
            None
        };
        if let Some((outcome, event)) = terminal {
            if let Some(open) = row.continuation.as_mut().or(row.stage.as_mut()) {
                self.tracker.close(open, tick);
            }
            row.outcome = outcome;
            row.receipts.push(receipt(event, tick, state, status));
        }
    }

    /// True while an attempt that entered the market is still unresolved.
    pub(super) fn in_market(&self) -> bool {
        self.metrics
            .attempts
            .last()
            .is_some_and(|row| row.outcome == Outcome::InProgress && row.stage.is_some())
    }

    /// Record one chosen action and its simulated result. Diagnostic only.
    pub(super) fn step(&mut self, decision: &stage::Decision<'_>, outcome: stage::Outcome<'_>) {
        if let Some(facts) = self
            .metrics
            .attempts
            .last_mut()
            .filter(|row| row.outcome == Outcome::InProgress)
            .and_then(|row| row.continuation.as_mut().or(row.stage.as_mut()))
        {
            self.tracker.step(facts, decision, outcome);
        }
    }

    pub(super) fn finish_attempt(
        &mut self,
        tick: u64,
        state: &MissionState,
        status: Option<Status>,
    ) {
        if let Some(row) = self
            .metrics
            .attempts
            .last_mut()
            .filter(|row| row.attempt == state.attempt && row.outcome == Outcome::InProgress)
        {
            if let Some(open) = row.continuation.as_mut().or(row.stage.as_mut()) {
                self.tracker.close(open, tick);
            }
            row.outcome = Outcome::Timeout;
            row.receipts
                .push(receipt(Event::Timeout, tick, state, status));
        }
    }

    pub(super) fn finish(self) -> Metrics {
        self.metrics
    }
}

fn receipt(event: Event, tick: u64, state: &MissionState, status: Option<Status>) -> Receipt {
    let facts = state.m19.as_ref();
    Receipt {
        event,
        tick,
        current_objective: facts
            .and_then(|facts| facts.current.as_ref())
            .map(|o| o.id.clone()),
        continues: state.run.map(|run| run.continues),
        status,
        attempt_paver_interrupted: facts.is_some_and(|facts| facts.challenges.paver_interrupted),
        attempt_strip_struck: facts.is_some_and(|facts| facts.challenges.strip_struck),
    }
}
