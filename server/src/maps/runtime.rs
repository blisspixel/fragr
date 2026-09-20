//! One map handle for simulation, controllers, spawns and wire presentation.

use super::authored::AuthoredMap;
use crate::movement::{Arena, Solid};
use crate::navigation::Navigation;
use crate::sim::{ArenaPickup, MapKind};
use std::sync::Arc;

#[derive(Debug, Clone)]
pub enum RuntimeMap {
    BuiltIn(MapKind),
    Authored(Arc<AuthoredMap>),
}

impl PartialEq for RuntimeMap {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::BuiltIn(a), Self::BuiltIn(b)) => a == b,
            (Self::Authored(a), Self::Authored(b)) => Arc::ptr_eq(a, b),
            _ => false,
        }
    }
}

impl PartialEq<MapKind> for RuntimeMap {
    fn eq(&self, other: &MapKind) -> bool {
        matches!(self, Self::BuiltIn(kind) if kind == other)
    }
}

impl RuntimeMap {
    pub(crate) fn encounters(&self) -> &[super::authored::encounters::EncounterDefinition] {
        match self {
            Self::BuiltIn(_) => &[],
            Self::Authored(map) => &map.encounters,
        }
    }

    pub fn has_encounters(&self) -> bool {
        !self.encounters().is_empty()
    }

    pub fn equipment_policy(&self) -> crate::protocol::EquipmentPolicy {
        match self {
            Self::BuiltIn(_) => crate::protocol::EquipmentPolicy::FullArsenal,
            Self::Authored(map) => map.equipment,
        }
    }

    pub fn id(&self) -> u32 {
        match self {
            Self::BuiltIn(kind) => kind.id(),
            Self::Authored(map) => map.id,
        }
    }

    pub fn name(&self) -> &str {
        match self {
            Self::BuiltIn(kind) => kind.name(),
            Self::Authored(map) => &map.name,
        }
    }

    pub fn arena(&self) -> &Arena {
        match self {
            Self::BuiltIn(kind) => super::arena(*kind),
            Self::Authored(map) => &map.arena,
        }
    }

    pub fn navigation(&self) -> &Navigation {
        match self {
            Self::BuiltIn(kind) => super::navigation(*kind),
            Self::Authored(map) => &map.navigation,
        }
    }

    pub fn is_authored(&self) -> bool {
        matches!(self, Self::Authored(_))
    }

    pub fn solids(&self) -> Vec<Solid> {
        self.arena().solids.clone()
    }

    pub fn presentation(&self) -> Option<crate::protocol::MapPresentation> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => Some(map.presentation.clone()),
        }
    }

    pub fn half_extent(&self) -> f32 {
        self.arena().half
    }

    pub(crate) fn pickups(&self) -> Vec<ArenaPickup> {
        match self {
            Self::BuiltIn(kind) => kind.pickups(),
            Self::Authored(map) => map.supplies.clone(),
        }
    }

    pub(crate) fn spawn_slots(&self) -> usize {
        match self {
            Self::BuiltIn(_) => 64,
            Self::Authored(map) => map.spawns.len(),
        }
    }

    pub(crate) fn spawn(&self, angle: f32) -> (f32, f32, f32, f32) {
        match self {
            Self::BuiltIn(kind) => crate::sim::spawn_on_ring(*kind, angle),
            Self::Authored(map) => {
                let index = (angle / std::f32::consts::TAU * map.spawns.len() as f32).round()
                    as usize
                    % map.spawns.len();
                let spawn = &map.spawns[index];
                (spawn.feet[0], spawn.feet[2], spawn.yaw, spawn.feet[1])
            }
        }
    }
}
