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
    pub(crate) fn m05_objectives(&self) -> Option<&super::authored::m05::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m05.as_deref(),
        }
    }
    pub fn m05_geometry(&self) -> Option<crate::protocol::M05MapGeometry> {
        let mut g = self.m05_objectives()?.geometry.clone();
        g.freight_open = matches!(self,Self::Authored(map) if map.freight_open);
        Some(g)
    }
    pub fn prepared_m05_world(&self) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let p = map.m05.as_ref()?;
        let mut selected = map.as_ref().clone();
        selected.arena = p.opened.clone();
        selected.navigation = p.navigation.clone();
        selected.freight_open = true;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub(crate) fn m04_objectives(&self) -> Option<&super::authored::m04::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m04.as_deref(),
        }
    }
    pub fn m04_geometry(&self) -> Option<crate::protocol::M04MapGeometry> {
        let mut geometry = self.m04_objectives()?.geometry.clone();
        geometry.clinic_open = matches!(self,Self::Authored(map) if map.clinic_open);
        Some(geometry)
    }
    pub fn prepared_m04_world(&self) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m04.as_ref()?;
        let mut selected = map.as_ref().clone();
        selected.arena = prepared.opened.clone();
        selected.navigation = prepared.navigation.clone();
        selected.clinic_open = true;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub(crate) fn m03_objectives(&self) -> Option<&super::authored::m03::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m03.as_deref(),
        }
    }

    pub fn m03_geometry(&self) -> Option<crate::protocol::M03MapGeometry> {
        let mut geometry = self.m03_objectives()?.geometry.clone();
        geometry.mast_shutdown = matches!(self, Self::Authored(map) if map.mast_shutdown);
        Some(geometry)
    }

    pub fn prepared_m03_world(&self) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m03.as_ref()?;
        let mut selected = map.as_ref().clone();
        selected.arena = prepared.fallen.clone();
        selected.navigation = prepared.navigation.clone();
        selected.mast_shutdown = true;
        for panel in &mut selected.presentation.decorations {
            if panel.kind == crate::protocol::MapDecorationKind::M03ScheduleBoard {
                panel.kind = crate::protocol::MapDecorationKind::M03ScheduleCancelled;
            }
        }
        Some(Self::Authored(Arc::new(selected)))
    }
    /// The authored side-ward encounter controls the matching map and mission wire marker.
    pub(crate) fn has_m02_side_ward(&self) -> bool {
        self.m02_objectives().is_some()
            && self
                .encounters()
                .iter()
                .any(|encounter| encounter.id == "side_ward_guards")
    }

    pub(crate) fn m02_objectives(&self) -> Option<&super::authored::m02::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m02.as_deref(),
        }
    }

    /// Identity of the exact authored bytes used to build this runtime map.
    /// An opened route retains the same identity as its closed source.
    pub fn content_sha256(&self) -> Option<[u8; 32]> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => Some(map.content_sha256),
        }
    }

    pub fn mission(&self) -> Option<&crate::protocol::MissionGeometry> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.mission.as_ref(),
        }
    }

    pub(crate) fn campaign_mission_id(&self) -> Option<crate::protocol::MissionId> {
        self.mission()
            .map(|mission| mission.id)
            .or_else(|| {
                self.m02_objectives()
                    .map(|_| crate::protocol::MissionId::PersonsUnknown)
            })
            .or_else(|| {
                self.m03_objectives()
                    .map(|_| crate::protocol::MissionId::ScheduledService)
            })
            .or_else(|| {
                self.m04_objectives()
                    .map(|_| crate::protocol::MissionId::NoticeToVacate)
            })
            .or_else(|| {
                self.m05_objectives()
                    .map(|_| crate::protocol::MissionId::NoForwardingAddress)
            })
    }

    pub fn opened_route(&self) -> Option<Self> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map
                .opened_route
                .as_ref()
                .map(|opened| Self::Authored(opened.clone())),
        }
    }

    /// Select one of the M02 worlds built and route-checked at map load time.
    /// No geometry or navigation is constructed on a live transition.
    pub fn prepared_gate_world(&self, mask: u8) -> Option<Self> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => {
                let prepared = map.m02.as_ref()?;
                let (arena, navigation) = prepared.world(mask)?;
                let mut selected = map.as_ref().clone();
                selected.arena = arena.clone();
                selected.navigation = navigation.clone();
                selected.presentation = prepared.presentation(mask)?.clone();
                Some(Self::Authored(Arc::new(selected)))
            }
        }
    }

    pub fn is_campaign(&self) -> bool {
        self.has_encounters()
            || self.mission().is_some()
            || matches!(self, Self::Authored(map) if map.m02.is_some() || map.m03.is_some() || map.m04.is_some() || map.m05.is_some())
    }

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
        self.presentation_ref().cloned()
    }

    pub fn presentation_ref(&self) -> Option<&crate::protocol::MapPresentation> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => Some(&map.presentation),
        }
    }

    pub fn half_extent(&self) -> f32 {
        self.arena().half
    }

    pub(crate) fn ctf_stands(&self) -> Option<[[f32; 3]; 2]> {
        match self {
            Self::BuiltIn(kind) => super::ctf_stands(*kind),
            Self::Authored(_) => None,
        }
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
