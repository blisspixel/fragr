//! Custody tender targets and resolved challenge facts. No dialogue grants history.
use super::{
    CampaignDifficulty, MapDecorationKind, MapPresentation, MissionObjective,
    MissionObjectiveAction, MissionPhase, Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

const MAX_EXACT_JSON_INTEGER: u64 = (1_u64 << 53) - 1;

fn present<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Deserialize<'de>,
{
    T::deserialize(deserializer).map(Some)
}

pub const M11_OBJECTIVE_IDS: [&str; 6] = [
    "armory_found",
    "spine_secured",
    "holds_secured",
    "records_secured",
    "counter_boarders_secured",
    "bridge_secured",
];
/// Prototype tender response window, from actual counter-boarding activation.
/// This new mission tune does not change earlier encounters or campaign rules.
pub const M11_SIGNAL_TICKS: u64 = 1200;

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M11MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub transfer_release: UseTarget,
    pub records_document: UseTarget,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub companion_start: [f32; 3],
    /// Anonymous people in transfer. No proposed identity or rescue history.
    pub transfer_people: Vec<[f32; 3]>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M11ChallengeState {
    pub transfer_released: bool,
    pub records_read: bool,
    /// Maximum kills of actual counter-boarders from one resolved charge blast.
    /// Neither cumulative kills nor simultaneously triggered separate charges.
    pub counter_boarder_blast_kills: u8,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub counter_boarding_started: Option<u64>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub signal_due: Option<u64>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub bridge_taken_at: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M11ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M11ChallengeState,
}

fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}

impl M11MapGeometry {
    pub fn validate(
        &self,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let present = presentation.ok_or("M11 presentation missing")?;
        if !half.is_finite()
            || !(2.0..=crate::movement::MAX_HALF_EXTENT).contains(&half)
            || self.objectives.len() != M11_OBJECTIVE_IDS.len()
            || self
                .objectives
                .iter()
                .zip(M11_OBJECTIVE_IDS)
                .any(|(o, id)| {
                    o.id != id
                        || !matches!(&o.action, MissionObjectiveAction::Arrival {region, feet}
                        if region.valid(half) && point(*feet, half) && region.contains(*feet))
                })
            || !self.boarding.valid(half)
            || !self.boarding.contains(self.departure.approach)
            || !point(self.companion_start, half)
            || self.transfer_people.len() != 3
            || self.transfer_people.iter().any(|p| !point(*p, half))
            || self.transfer_people.iter().enumerate().any(|(i, a)| {
                self.transfer_people[..i]
                    .iter()
                    .any(|b| (a[0] - b[0]).hypot(a[2] - b[2]) < 2.0 * crate::movement::RADIUS)
            })
        {
            return Err("invalid M11 map objectives or transfer positions");
        }
        let targets = [
            (
                &self.transfer_release,
                MapDecorationKind::M11TransferRelease,
            ),
            (
                &self.records_document,
                MapDecorationKind::M11RecordsDocument,
            ),
            (&self.departure, MapDecorationKind::M11SternRelease),
        ];
        if targets.iter().enumerate().any(|(i, (target, kind))| {
            !point(target.approach, half)
                || target.point(present, solids).is_none()
                || present
                    .decorations
                    .get(target.decoration)
                    .is_none_or(|d| d.kind != *kind)
                || targets[..i]
                    .iter()
                    .any(|(other, _)| other.decoration == target.decoration)
        }) {
            return Err("invalid M11 registered use targets");
        }
        Ok(())
    }
}

impl M11ChallengeState {
    pub fn validate(&self, tick: u64) -> Result<(), &'static str> {
        if tick > MAX_EXACT_JSON_INTEGER
            || self
                .signal_due
                .is_some_and(|due| due > MAX_EXACT_JSON_INTEGER)
            || self.counter_boarder_blast_kills > 6
        {
            return Err("M11 single-charge result exceeds actual counter-boarder roster");
        }
        match (self.counter_boarding_started, self.signal_due) {
            (None, None)
                if self.counter_boarder_blast_kills == 0 && self.bridge_taken_at.is_none() => {}
            (Some(start), Some(due))
                if start <= tick && start.checked_add(M11_SIGNAL_TICKS) == Some(due) => {}
            _ => return Err("invalid M11 counter-boarding clock"),
        }
        if self.bridge_taken_at.is_some_and(|taken| {
            taken > tick
                || self
                    .counter_boarding_started
                    .is_none_or(|start| taken < start)
        }) {
            return Err("invalid M11 bridge receipt");
        }
        Ok(())
    }

    /// Brief completion is a resolved fact, not an extra departure gate.
    pub fn brief_completed(&self, difficulty: CampaignDifficulty) -> bool {
        self.transfer_released
            && (difficulty == CampaignDifficulty::Assisted || self.counter_boarder_blast_kills >= 3)
            && (difficulty != CampaignDifficulty::Severe
                || matches!((self.bridge_taken_at, self.signal_due), (Some(taken), Some(due)) if taken < due))
    }
}

impl M11ObjectiveState {
    pub fn validate(&self, phase: MissionPhase, tick: u64) -> Result<(), &'static str> {
        self.challenges.validate(tick)?;
        let count = self.completed.len();
        let order = |i: usize| {
            M11_OBJECTIVE_IDS
                .get(i)
                .copied()
                .unwrap_or("party_departed")
        };
        if !matches!(
            phase,
            MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
        ) || count > M11_OBJECTIVE_IDS.len() + 1
            || self
                .completed
                .iter()
                .enumerate()
                .any(|(i, id)| id != order(i))
            || (phase == MissionPhase::Departed) != (count == M11_OBJECTIVE_IDS.len() + 1)
            || self.current.is_some() != (count <= M11_OBJECTIVE_IDS.len())
            || phase == MissionPhase::Briefing
                && (count != 0 || self.challenges != M11ChallengeState::default())
            || self.challenges.counter_boarding_started.is_some() && count < 3
            || count >= 5 && self.challenges.counter_boarding_started.is_none()
            || (self.challenges.bridge_taken_at.is_some() != (count >= 6))
            || self.challenges.records_read && count < 4
            || self.challenges.transfer_released && count < 3
        {
            return Err("invalid M11 objective and challenge progression");
        }
        if let Some(current) = &self.current {
            if current.id != order(count) {
                return Err("invalid M11 current objective identity");
            }
            match &current.action {
                MissionObjectiveAction::Arrival { region, feet }
                    if count < M11_OBJECTIVE_IDS.len()
                        && region.valid(512.0)
                        && point(*feet, 512.0)
                        && region.contains(*feet) => {}
                MissionObjectiveAction::Use { target }
                    if count == M11_OBJECTIVE_IDS.len()
                        && point(target.approach, 512.0)
                        && target.decoration < super::MAX_MAP_DECORATIONS => {}
                _ => return Err("invalid M11 current objective action"),
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests;
