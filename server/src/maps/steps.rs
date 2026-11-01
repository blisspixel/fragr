//! The world changes a level makes as it is played, as a replayable list.
//!
//! Every live transition selects one of the worlds the map prepared at load
//! time (a door opened, a machine fallen, a stage reached). A saved
//! checkpoint keeps the steps taken since the level entry, and a reopened run
//! rebuilds the same world by taking them again from the entry map. No
//! geometry is ever read from a save file.
use super::RuntimeMap;
use serde::{Deserialize, Serialize};

/// The most steps one level can take; a longer list is refused.
pub(crate) const MAX_MAP_STEPS: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum MapStep {
    /// The transfer route of a find-the-transfer mission opened.
    OpenedRoute,
    /// M02's gate world for this mask, chosen from the entry map.
    M02Gate {
        mask: u8,
    },
    M03Fallen,
    M04Opened,
    M05Opened,
    /// M08's stage, chosen from the entry map.
    M08 {
        stage: u8,
    },
    M09Opened,
    M12Shelter,
    /// The Walker's fallen hull at the feet it fell at.
    M14Fallen {
        feet: [f32; 3],
    },
    M15 {
        stage: u8,
    },
    M16 {
        stage: u8,
    },
    M17 {
        stage: u8,
    },
    M18 {
        stage: u8,
    },
    M19 {
        stage: u8,
    },
    M20 {
        stage: u8,
    },
}

impl MapStep {
    /// The world after this step from `current`, a level whose entry map is
    /// `initial`. None when the step does not apply to this map.
    pub(crate) fn apply(self, current: &RuntimeMap, initial: &RuntimeMap) -> Option<RuntimeMap> {
        match self {
            Self::OpenedRoute => current.opened_route(),
            Self::M02Gate { mask } => initial.prepared_gate_world(mask),
            Self::M03Fallen => initial.prepared_m03_world(),
            Self::M04Opened => current.prepared_m04_world(),
            Self::M05Opened => current.prepared_m05_world(),
            Self::M08 { stage } => initial.prepared_m08_world(stage),
            Self::M09Opened => current.prepared_m09_world(),
            Self::M12Shelter => current.prepared_m12_world(),
            Self::M14Fallen { feet } => feet
                .iter()
                .all(|v| v.is_finite())
                .then(|| current.prepared_m14_world(feet))
                .flatten(),
            Self::M15 { stage } => current.prepared_m15_world(stage),
            Self::M16 { stage } => current.prepared_m16_world(stage),
            Self::M17 { stage } => current.prepared_m17_world(stage),
            Self::M18 { stage } => current.prepared_m18_world(stage),
            Self::M19 { stage } => current.prepared_m19_world(stage),
            Self::M20 { stage } => current.prepared_m20_world(stage),
        }
    }

    /// The world `steps` lead to from the entry map, or None if any step
    /// does not apply.
    pub(crate) fn replay(steps: &[Self], initial: &RuntimeMap) -> Option<RuntimeMap> {
        if steps.len() > MAX_MAP_STEPS {
            return None;
        }
        let mut world = initial.clone();
        for step in steps {
            world = step.apply(&world, initial)?;
        }
        Some(world)
    }
}
