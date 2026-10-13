//! Authoritative foundry progression and bounded moving-world facts.
use super::{
    MapDecorationKind, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};
pub const M13_OBJECTIVE_IDS: [&str; 7] = [
    "foundry_entered",
    "machine_hall_cleared",
    "rocket_found",
    "freight_loop_secured",
    "relay_disabled",
    "upper_gallery_secured",
    "lift_boarded",
];
pub const M13_LIFT_SPEED: f32 = 1.5;
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum M13WorkerResponse {
    Volunteered,
    DepartedIndependently,
    DeclinedAndKeptWorking,
}
pub const M13_WORKER_RESPONSES: [M13WorkerResponse; 3] = [
    M13WorkerResponse::Volunteered,
    M13WorkerResponse::DepartedIndependently,
    M13WorkerResponse::DeclinedAndKeptWorking,
];
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum M13LiftPhase {
    Parked,
    Moving,
    Returning,
    Blocked,
    Arrived,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum M13HazardPhase {
    Idle,
    Warning,
    Active,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M13HazardCycle {
    pub period: u32,
    pub warning: u32,
    pub active: u32,
}
impl M13HazardCycle {
    pub fn validate(self) -> Result<(), &'static str> {
        if self.period > 400
            || self.warning == 0
            || self.active == 0
            || self.warning.saturating_add(self.active) >= self.period
        {
            Err("invalid foundry hazard cycle")
        } else {
            Ok(())
        }
    }
    pub fn phase(self, tick: u64) -> M13HazardPhase {
        let place = (tick % u64::from(self.period.max(1))) as u32;
        let idle = self
            .period
            .saturating_sub(self.warning.saturating_add(self.active));
        if place < idle {
            M13HazardPhase::Idle
        } else if place < idle + self.warning {
            M13HazardPhase::Warning
        } else {
            M13HazardPhase::Active
        }
    }
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M13MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub release: UseTarget,
    pub departure: UseTarget,
    pub relay: usize,
    pub protected: Vec<usize>,
    pub hazard: Region3,
    pub bypass: Region3,
    pub cycle: M13HazardCycle,
    pub deck: usize,
    pub parked_top: f32,
    pub lift_top: f32,
    pub inset_min: [f32; 2],
    pub inset_max: [f32; 2],
    pub workers: [[f32; 3]; 3],
    pub worker_destinations: [[f32; 3]; 3],
    pub overseer: [f32; 3],
}
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M13ChallengeState {
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub workers: Option<[M13WorkerResponse; 3]>,
    pub workers_arrived: [bool; 3],
    pub hazard_hurt: u64,
    pub supports_cleared: bool,
}
impl M13ChallengeState {
    pub fn brief_completed(&self, difficulty: super::CampaignDifficulty) -> bool {
        self.workers.is_some()
            && (difficulty == super::CampaignDifficulty::Assisted || self.supports_cleared)
            && (difficulty != super::CampaignDifficulty::Severe || self.hazard_hurt == 0)
    }
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.hazard_hurt > (1u64 << 53) - 1
            || self.workers.is_some_and(|w| w != M13_WORKER_RESPONSES)
            || self.workers_arrived[2]
            || self.workers.is_none() && self.workers_arrived.iter().any(|v| *v)
        {
            Err("invalid foundry worker or hazard receipts")
        } else {
            Ok(())
        }
    }
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M13LiftState {
    pub phase: M13LiftPhase,
    pub top: f32,
    pub tick: u64,
    pub returning: bool,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M13ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M13ChallengeState,
    pub relay_disabled: bool,
    pub overseer_surrendered: bool,
    pub worker_feet: [[f32; 3]; 3],
    pub lift: M13LiftState,
    pub hazard_phase: M13HazardPhase,
}
fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}
impl M13MapGeometry {
    pub fn upper_boarding(&self) -> Region3 {
        Region3 {
            min: [self.inset_min[0], self.lift_top - 0.06, self.inset_min[1]],
            max: [self.inset_max[0], self.lift_top + 0.06, self.inset_max[1]],
        }
    }
    pub fn departure_objective(&self) -> MissionObjective {
        let region = self.upper_boarding();
        MissionObjective {
            id: "party_departed".into(),
            action: MissionObjectiveAction::Arrival {
                feet: [
                    (self.inset_min[0] + self.inset_max[0]) * 0.5,
                    self.lift_top,
                    (self.inset_min[1] + self.inset_max[1]) * 0.5,
                ],
                region,
            },
        }
    }
    pub fn validate(
        &self,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let p = presentation.ok_or("M13 presentation missing")?;
        self.cycle.validate()?;
        let deck = solids.get(self.deck).ok_or("M13 deck missing")?;
        if !half.is_finite()
            || !(2.0..=crate::movement::MAX_HALF_EXTENT).contains(&half)
            || self.relay >= solids.len()
            || self.protected.is_empty()
            || self.protected.iter().enumerate().any(|(i, s)| {
                *s >= solids.len()
                    || *s == self.relay
                    || *s == self.deck
                    || self.protected[..i].contains(s)
            })
            || !self.hazard.valid(half)
            || !self.bypass.valid(half)
            || (0..3).all(|i| {
                self.hazard.min[i] < self.bypass.max[i] && self.bypass.min[i] < self.hazard.max[i]
            })
            || !self.parked_top.is_finite()
            || !self.lift_top.is_finite()
            || self.lift_top <= self.parked_top
            || self.lift_top > 512.0
            || (deck.top - self.parked_top).abs() > 0.001
            || self
                .inset_min
                .iter()
                .chain(&self.inset_max)
                .any(|v| !v.is_finite())
            || self.inset_min[0] >= self.inset_max[0]
            || self.inset_min[1] >= self.inset_max[1]
            || !deck.covers(self.inset_min[0], self.inset_min[1])
            || !deck.covers(self.inset_max[0], self.inset_max[1])
            || self
                .workers
                .iter()
                .chain(&self.worker_destinations)
                .chain(std::iter::once(&self.overseer))
                .any(|v| !point(*v, half))
            || self.worker_destinations[2] != self.workers[2]
        {
            return Err("invalid M13 foundry geometry");
        }
        for (target, kind) in [
            (&self.release, MapDecorationKind::Terminal),
            (&self.departure, MapDecorationKind::LiftControl),
        ] {
            if !point(target.approach, half)
                || target.point(p, solids).is_none()
                || p.decorations
                    .get(target.decoration)
                    .is_none_or(|d| d.kind != kind)
            {
                return Err("invalid M13 physical control");
            }
        }
        if self.release.decoration == self.departure.decoration
            || p.decorations[self.departure.decoration].solid != self.deck
            || self.objectives.len() != 7
        {
            return Err("invalid M13 objective count or deck control");
        }
        for (i, (o, id)) in self.objectives.iter().zip(M13_OBJECTIVE_IDS).enumerate() {
            if o.id != id
                || match &o.action {
                    MissionObjectiveAction::Arrival { region, feet } => {
                        i == 4
                            || i == 6
                            || !region.valid(half)
                            || !point(*feet, half)
                            || !region.contains(*feet)
                    }
                    MissionObjectiveAction::Shoot {
                        solid,
                        approach,
                        aim,
                    } => {
                        i != 4
                            || *solid != self.relay
                            || !point(*approach, half)
                            || !point(*aim, half)
                    }
                    MissionObjectiveAction::Use { target } => i != 6 || target != &self.departure,
                }
            {
                return Err("invalid M13 ordered objective geometry");
            }
        }
        Ok(())
    }
}
impl M13ObjectiveState {
    pub fn validate(&self, phase: MissionPhase, tick: u64) -> Result<(), &'static str> {
        self.challenges.validate()?;
        let n = self.completed.len();
        let order = |i: usize| {
            M13_OBJECTIVE_IDS
                .get(i)
                .copied()
                .unwrap_or("party_departed")
        };
        if !matches!(
            phase,
            MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
        ) || n > 8
            || self
                .completed
                .iter()
                .enumerate()
                .any(|(i, s)| s != order(i))
            || (phase == MissionPhase::Departed) != (n == 8)
            || self.current.is_some() != (n < 8)
            || self.current.as_ref().is_some_and(|c| c.id != order(n))
            || self.lift.tick != tick
            || !self.lift.top.is_finite()
            || !(0.0..=512.0).contains(&self.lift.top)
            || self.worker_feet.iter().any(|p| !point(*p, 512.0))
            || self.relay_disabled != (n >= 5)
            || self.challenges.supports_cleared != (n >= 6)
            || self.challenges.workers.is_some() && !self.overseer_surrendered
            || n >= 3 && !self.overseer_surrendered
            || n < 7 && self.lift.phase != M13LiftPhase::Parked
            || self.lift.returning
                && !matches!(
                    self.lift.phase,
                    M13LiftPhase::Returning | M13LiftPhase::Blocked
                )
            || self.lift.phase == M13LiftPhase::Returning && !self.lift.returning
            || n == 8 && self.lift.phase != M13LiftPhase::Arrived
            || phase == MissionPhase::Briefing
                && (n != 0
                    || self.overseer_surrendered
                    || self.challenges != M13ChallengeState::default())
        {
            return Err("invalid M13 ordered progression");
        }
        if let Some(o) = &self.current {
            if match &o.action {
                MissionObjectiveAction::Arrival { region, feet } => {
                    n == 4
                        || n == 6
                        || !region.valid(512.0)
                        || !point(*feet, 512.0)
                        || !region.contains(*feet)
                }
                MissionObjectiveAction::Shoot {
                    solid,
                    approach,
                    aim,
                } => {
                    n != 4
                        || *solid >= crate::movement::MAX_SOLIDS
                        || !point(*approach, 512.0)
                        || !point(*aim, 512.0)
                }
                MissionObjectiveAction::Use { target } => {
                    n != 6
                        || target.decoration >= super::MAX_MAP_DECORATIONS
                        || !point(target.approach, 512.0)
                }
            } {
                return Err("invalid M13 current action");
            }
        }
        Ok(())
    }
}
