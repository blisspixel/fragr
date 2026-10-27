//! Observer-only receipts for the bounded Planned Works lesson. Nothing in
//! this module feeds the controller or changes simulation state.
use super::{Profile, DT};
use fragr_server::movement::{grounded, Arena};
use fragr_server::protocol::{
    CampaignDifficulty, MissionState, PlayerState, ServerMessage, Snapshot,
};
use fragr_server::sim::PLAYER_FLOOR_Y;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, VecDeque};
use uuid::Uuid;

#[cfg(test)]
mod tests;

/// The public objective boundary, not an assertion about encounter activation.
#[derive(Debug, Default, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum Stage {
    #[default]
    Teaching,
    Market,
    /// After `market_strips`, only when the survey continues to the tanks.
    Tanks,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize, PartialEq)]
pub struct Metrics {
    pub objectives: Vec<Receipt>,
    pub flights: Vec<Flight>,
    pub paver_phases: Vec<PaverPhase>,
    pub interrupted_attempts: Vec<u32>,
    pub strip_struck_attempts: Vec<u32>,
    pub supported_refuel_ticks: u32,
    pub airborne_refuel_ticks: u32,
    pub observation_gaps: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Receipt {
    pub objective: String,
    pub attempt: u32,
    pub tick: u64,
    pub feet: [f32; 3],
    pub fuel: Option<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Flight {
    pub attempt: u32,
    pub started_tick: u64,
    /// Last live sample of this flight, not a later death or retry boundary.
    pub ended_tick: u64,
    pub from: [f32; 3],
    pub to: [f32; 3],
    pub initial_fuel: u16,
    pub minimum_fuel: u16,
    pub burn_ticks: u32,
    pub maximum_feet_height: f32,
    pub ending: String,
    pub gallery_landing: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PaverPhase {
    pub owner: Uuid,
    pub attempt: u32,
    pub stage: Stage,
    pub started_tick: u64,
    pub first_snapshot_tick: u64,
    /// First recognized sample in this stage, not necessarily initial acquisition.
    pub recognized_tick: Option<u64>,
    pub working: bool,
}

struct Window {
    event: &'static str,
    attempt: u32,
    stage: Stage,
    view: PlayerState,
    map_info: ServerMessage,
    frames: Vec<Snapshot>,
    active_stall_seconds: Option<f64>,
}

pub(super) struct Recorder {
    id: Uuid,
    seed: u64,
    profile: Profile,
    difficulty: CampaignDifficulty,
    record: bool,
    attempt: u32,
    stage: Stage,
    metrics: Metrics,
    flight: Option<usize>,
    previous_fuel: Option<u16>,
    last_tick: Option<u64>,
    recent: VecDeque<Snapshot>,
    windows: Vec<Window>,
    seen_windows: BTreeSet<(u32, Stage, &'static str)>,
    /// Label steps after `market_strips` as their own stage.
    through_tanks: bool,
}

impl Recorder {
    /// Keep recording past the market under a separate tanks stage.
    pub(super) fn through_tanks(mut self) -> Self {
        self.through_tanks = true;
        self
    }

    pub(super) fn new(
        id: Uuid,
        seed: u64,
        profile: Profile,
        difficulty: CampaignDifficulty,
        record: bool,
    ) -> Self {
        Self {
            id,
            seed,
            profile,
            difficulty,
            record,
            attempt: 0,
            stage: Stage::Teaching,
            metrics: Metrics::default(),
            flight: None,
            previous_fuel: None,
            last_tick: None,
            recent: VecDeque::new(),
            windows: Vec::new(),
            seen_windows: BTreeSet::new(),
            through_tanks: false,
        }
    }

    /// Return only whether public objective progress changed. Grounding uses
    /// the authoritative vertical velocity solely to qualify this receipt.
    pub(super) fn observe(
        &mut self,
        snapshot: &Snapshot,
        state: &MissionState,
        arena: &Arena,
        vertical_velocity: Option<f32>,
        map_info: &ServerMessage,
    ) -> bool {
        if self.attempt != state.attempt {
            self.end_flight("retry");
            self.attempt = state.attempt;
            self.previous_fuel = None;
            self.last_tick = None;
            self.recent.clear();
        }
        if self.last_tick == Some(snapshot.tick) {
            return false;
        }
        if self
            .last_tick
            .is_some_and(|tick| tick.checked_add(1) != Some(snapshot.tick))
        {
            self.metrics.observation_gaps += 1;
            self.end_flight("observation_gap");
            self.previous_fuel = None;
            self.recent.clear();
        }
        self.last_tick = Some(snapshot.tick);
        let Some(me) = snapshot
            .players
            .iter()
            .find(|p| p.id == self.id && p.hp > 0)
        else {
            self.end_flight("death");
            self.previous_fuel = None;
            self.recent.clear();
            return false;
        };
        let Some(facts) = &state.m19 else {
            return false;
        };
        let stage = if self.through_tanks
            && facts
                .completed
                .iter()
                .any(|objective| objective == "market_strips")
        {
            Stage::Tanks
        } else if facts
            .completed
            .iter()
            .any(|objective| objective == "tram_street")
        {
            Stage::Market
        } else {
            Stage::Teaching
        };
        if self.stage != stage {
            self.stage = stage;
            // A street pre-roll cannot stand in for a market window. Neither
            // perception nor flight/fuel history resets at this public boundary.
            self.recent.clear();
        }
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let pack = snapshot
            .jetpacks
            .iter()
            .find(|pack| pack.player_id == self.id);
        if pack.is_none() {
            self.previous_fuel = None;
            self.end_flight("pack_missing");
        }
        let mut advanced = false;
        for objective in &facts.completed {
            if !self
                .metrics
                .objectives
                .iter()
                .any(|receipt| receipt.attempt == self.attempt && receipt.objective == *objective)
            {
                self.metrics.objectives.push(Receipt {
                    objective: objective.clone(),
                    attempt: self.attempt,
                    tick: snapshot.tick,
                    feet,
                    fuel: pack.map(|pack| pack.fuel),
                });
                advanced = true;
            }
        }
        if facts.challenges.paver_interrupted
            && !self.metrics.interrupted_attempts.contains(&self.attempt)
        {
            self.metrics.interrupted_attempts.push(self.attempt);
        }
        if facts.challenges.strip_struck
            && !self.metrics.strip_struck_attempts.contains(&self.attempt)
        {
            self.metrics.strip_struck_attempts.push(self.attempt);
        }
        if self.record {
            for window in &mut self.windows {
                if window.attempt == self.attempt
                    && window.stage == self.stage
                    && window.frames.len() < 160
                    && window
                        .frames
                        .last()
                        .is_some_and(|last| last.tick + 1 == snapshot.tick)
                {
                    window.frames.push(snapshot.clone());
                }
            }
            self.recent.push_back(snapshot.clone());
            if self.recent.len() > 20 {
                self.recent.pop_front();
            }
        }
        let supported = vertical_velocity.is_some_and(|vy| {
            grounded(feet[1], arena.support_height(feet[0], feet[2], feet[1]), vy)
        });
        if let Some(pack) = pack {
            if self.previous_fuel.is_some_and(|fuel| pack.fuel > fuel) {
                if supported {
                    self.metrics.supported_refuel_ticks += 1;
                } else {
                    self.metrics.airborne_refuel_ticks += 1;
                }
            }
            self.previous_fuel = Some(pack.fuel);
            if self.flight.is_none() && !supported {
                self.flight = Some(self.metrics.flights.len());
                self.metrics.flights.push(Flight {
                    attempt: self.attempt,
                    started_tick: snapshot.tick,
                    ended_tick: snapshot.tick,
                    from: feet,
                    to: feet,
                    initial_fuel: pack.fuel,
                    minimum_fuel: pack.fuel,
                    burn_ticks: 0,
                    maximum_feet_height: feet[1],
                    ending: "airborne".into(),
                    gallery_landing: false,
                });
            }
            if let Some(index) = self.flight {
                let flight = &mut self.metrics.flights[index];
                flight.ended_tick = snapshot.tick;
                flight.to = feet;
                flight.minimum_fuel = flight.minimum_fuel.min(pack.fuel);
                flight.burn_ticks += u32::from(pack.thrusting);
                flight.maximum_feet_height = flight.maximum_feet_height.max(feet[1]);
                if supported {
                    flight.ending = "supported".into();
                    flight.gallery_landing = flight.burn_ticks > 0 && match map_info {
                        ServerMessage::MapInfo { m19: Some(geometry), .. } => {
                            geometry.jet_hops.first().is_some_and(|hop| {
                                flight.from[1] < hop.landing[1] - 0.5
                                    && (feet[1] - hop.landing[1]).abs() <= 0.05
                                    && geometry.objectives.get(1).is_some_and(|objective| {
                                        matches!(&objective.action,
                                            fragr_server::protocol::MissionObjectiveAction::Arrival { region, .. }
                                            if region.contains(feet))
                                    })
                            })
                        }
                        _ => false,
                    };
                    self.flight = None;
                }
            }
            if pack.thrusting {
                self.window("jetpack_flight", me, map_info);
            }
        }
        if self.stage == Stage::Tanks {
            // The walk out of the market, then the first rise toward the
            // tank top, whichever way the body gets there.
            self.window("tanks_leg", me, map_info);
            // Open only once the retained pre-roll already shows more than a
            // metre of rise, so every climb window carries its own baseline.
            let baseline = self
                .recent
                .front()
                .and_then(|frame| frame.players.iter().find(|p| p.id == self.id).map(|p| p.y));
            if baseline.is_some_and(|y| me.y - y > 1.0) {
                self.window("tanks_climb", me, map_info);
            }
        }
        for strip in &snapshot.paver_strips {
            if !self.metrics.paver_phases.iter().any(|phase| {
                phase.attempt == self.attempt
                    && phase.stage == self.stage
                    && phase.owner == strip.owner_id
                    && phase.started_tick == strip.phase_started
                    && phase.working == strip.working
            }) {
                self.metrics.paver_phases.push(PaverPhase {
                    owner: strip.owner_id,
                    attempt: self.attempt,
                    stage: self.stage,
                    started_tick: strip.phase_started,
                    first_snapshot_tick: snapshot.tick,
                    recognized_tick: None,
                    working: strip.working,
                });
                self.window(
                    if strip.working {
                        "paver_work"
                    } else {
                        "paver_tell"
                    },
                    me,
                    map_info,
                );
            }
        }
        // Overlap here is temporal: two distinct owners publish strips in the
        // same snapshot. It does not claim intersecting ground rectangles.
        if snapshot.paver_strips.first().is_some_and(|first| {
            snapshot
                .paver_strips
                .iter()
                .any(|strip| strip.owner_id != first.owner_id)
        }) {
            self.window("paver_overlap", me, map_info);
        }
        advanced
    }

    pub(super) fn observe_perception(&mut self, observed: &Snapshot) {
        for strip in &observed.paver_strips {
            if let Some(phase) = self.metrics.paver_phases.iter_mut().find(|phase| {
                phase.attempt == self.attempt
                    && phase.stage == self.stage
                    && phase.owner == strip.owner_id
                    && phase.started_tick == strip.phase_started
                    && phase.working == strip.working
            }) {
                phase.recognized_tick.get_or_insert(observed.tick);
            }
        }
    }

    fn window(&mut self, event: &'static str, me: &PlayerState, map_info: &ServerMessage) {
        if self.record && self.seen_windows.insert((self.attempt, self.stage, event)) {
            self.windows.push(Window {
                event,
                attempt: self.attempt,
                stage: self.stage,
                view: me.clone(),
                map_info: map_info.clone(),
                frames: self.recent.iter().cloned().collect(),
                active_stall_seconds: None,
            });
        }
    }

    pub(super) fn observe_stall(
        &mut self,
        seconds: f64,
        me: &PlayerState,
        map_info: &ServerMessage,
    ) {
        if seconds.is_finite() && seconds >= 10.0 && me.hp > 0 {
            let count = self.windows.len();
            self.window("active_stall", me, map_info);
            if self.windows.len() > count {
                self.windows.last_mut().unwrap().active_stall_seconds = Some(seconds);
            }
        }
    }

    fn end_flight(&mut self, ending: &str) {
        if let Some(index) = self.flight.take() {
            self.metrics.flights[index].ending = ending.into();
        }
    }

    pub(super) fn finish(mut self) -> (Metrics, Vec<serde_json::Value>) {
        self.end_flight("trial_end");
        let windows = self
            .windows
            .into_iter()
            .map(|window| {
                serde_json::json!({
                    "event": window.event, "seed": self.seed, "profile": self.profile.name,
                    "difficulty": self.difficulty, "attempt": window.attempt,
                    "stage": window.stage, "view": window.view,
                    "map_info": window.map_info, "snapshot": window.frames.first(),
                    "frames": window.frames, "step_seconds": DT,
                    "active_stall_seconds": window.active_stall_seconds,
                })
            })
            .collect();
        (self.metrics, windows)
    }
}
