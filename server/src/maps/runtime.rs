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
    pub(crate) fn m19_objectives(&self) -> Option<&super::authored::m19::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m19.as_deref(),
        }
    }
    pub fn m19_geometry(&self) -> Option<crate::protocol::M19MapGeometry> {
        let mut geometry = self.m19_objectives()?.geometry.clone();
        geometry.gate_open = self.m19_stage() >= 1;
        Some(geometry)
    }
    /// 0 initial, 1 waterworks gate open.
    pub fn m19_stage(&self) -> u8 {
        match self {
            Self::Authored(map) if map.m19.is_some() => map.m19_stage,
            _ => 0,
        }
    }
    pub fn prepared_m19_world(&self, stage: u8) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m19.as_ref()?;
        let mut selected = map.as_ref().clone();
        match stage {
            0 => {
                selected.arena = prepared.initial.clone();
                selected.navigation = prepared.navigation.clone();
            }
            1 => {
                selected.arena = prepared.open.clone();
                selected.navigation = prepared.open_navigation.clone();
            }
            _ => return None,
        }
        selected.m19_stage = stage;
        Some(Self::Authored(Arc::new(selected)))
    }
    /// Feet never rise above this under jetpack thrust on this map.
    pub fn jetpack_ceiling(&self) -> f32 {
        self.m19_objectives()
            .map_or(crate::movement::jetpack::DEFAULT_CEILING, |prepared| {
                prepared.geometry.jetpack_ceiling
            })
    }
    pub(crate) fn m20_objectives(&self) -> Option<&super::authored::m20::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m20.as_deref(),
        }
    }
    pub fn m20_geometry(&self) -> Option<crate::protocol::M20MapGeometry> {
        let mut geometry = self.m20_objectives()?.geometry.clone();
        geometry.gate_open = self.m20_stage() >= 1;
        Some(geometry)
    }
    /// 0 refuge gate shut, 1 refuge gate open after the reprieve.
    pub fn m20_stage(&self) -> u8 {
        match self {
            Self::Authored(map) if map.m20.is_some() => map.m20_stage,
            _ => 0,
        }
    }
    pub fn prepared_m20_world(&self, stage: u8) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m20.as_ref()?;
        let mut selected = map.as_ref().clone();
        selected.presentation = prepared.presentation.clone();
        match stage {
            0 => {
                selected.arena = prepared.initial.clone();
                selected.navigation = prepared.navigation.clone();
            }
            1 => {
                selected.arena = prepared.opened.clone();
                selected.navigation = prepared.opened_navigation.clone();
                // The gate's painted notice lies flat with the opened leaf.
                for panel in &mut selected.presentation.decorations {
                    if panel.solid == prepared.gate {
                        panel.face = crate::protocol::MapFace::Up;
                        panel.center = [0.0; 2];
                        panel.size = [0.25, 4.4];
                    }
                }
            }
            _ => return None,
        }
        selected.m20_stage = stage;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub(crate) fn epilogue_objectives(&self) -> Option<&super::authored::epilogue::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.epilogue.as_deref(),
        }
    }
    pub fn epilogue_geometry(&self) -> Option<crate::protocol::EpilogueMapGeometry> {
        let mut geometry = self.epilogue_objectives()?.geometry.clone();
        geometry.later = self.epilogue_stage() >= 1;
        Some(geometry)
    }
    /// 0 the first light after the reprieve, 1 the same refuge years later.
    pub fn epilogue_stage(&self) -> u8 {
        match self {
            Self::Authored(map) if map.epilogue.is_some() => map.epilogue_stage,
            _ => 0,
        }
    }
    pub fn prepared_epilogue_world(&self, stage: u8) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.epilogue.as_ref()?;
        let mut selected = map.as_ref().clone();
        match stage {
            0 => {
                selected.arena = prepared.aftermath.clone();
                selected.navigation = prepared.aftermath_navigation.clone();
                selected.name = super::authored::epilogue::NAME.into();
            }
            1 => {
                selected.arena = prepared.later.clone();
                selected.navigation = prepared.later_navigation.clone();
                // The same place under its later name: presenters light it
                // as a morning years on, not the first light.
                selected.name = super::authored::epilogue::LATER_NAME.into();
            }
            _ => return None,
        }
        selected.epilogue_stage = stage;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub fn requires_surveyor_contract(&self) -> bool {
        self.encounters().iter().any(|group| {
            group
                .enemies
                .iter()
                .any(|enemy| enemy.kind == crate::protocol::EnemyKind::Surveyor)
        })
    }
    pub(crate) fn m18_objectives(&self) -> Option<&super::authored::m18::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m18.as_deref(),
        }
    }
    pub fn m18_geometry(&self) -> Option<crate::protocol::M18MapGeometry> {
        let mut geometry = self.m18_objectives()?.geometry.clone();
        let stage = self.m18_stage();
        geometry.roadblock_active = stage >= 1;
        geometry.concourse_evac_completed = stage >= 2;
        Some(geometry)
    }
    /// 0 initial, 1 ruptured (maint gate open), 2 concourse evac secured (departure gate open).
    pub fn m18_stage(&self) -> u8 {
        match self {
            Self::Authored(map) if map.m18.is_some() => map.m18_stage,
            _ => 0,
        }
    }
    pub fn prepared_m18_world(&self, stage: u8) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m18.as_ref()?;
        let mut selected = map.as_ref().clone();
        selected.presentation = prepared.presentation.clone();
        // Keep decoration indices stable because UseTarget addresses them.
        // Recessed gate controls become horizontal floor plates when lowered.
        for panel in &mut selected.presentation.decorations {
            if stage >= 1 && panel.solid == prepared.maint_gate
                || stage >= 2 && panel.solid == prepared.departure_gate
            {
                panel.face = crate::protocol::MapFace::Up;
                panel.center = [0.0; 2];
            }
        }
        match stage {
            0 => {
                selected.arena = prepared.initial.clone();
                selected.navigation = prepared.navigation.clone();
            }
            1 => {
                selected.arena = prepared.ruptured.clone();
                selected.navigation = prepared.ruptured_navigation.clone();
            }
            2 => {
                selected.arena = prepared.concluded.clone();
                selected.navigation = prepared.concluded_navigation.clone();
            }
            _ => return None,
        }
        selected.m18_stage = stage;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub(crate) fn m17_objectives(&self) -> Option<&super::authored::m17::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m17.as_deref(),
        }
    }
    pub fn m17_geometry(&self) -> Option<crate::protocol::M17MapGeometry> {
        let mut geometry = self.m17_objectives()?.geometry.clone();
        let stage = self.m17_stage();
        geometry.core_unsealed = stage >= 1;
        geometry.voss_captured = stage >= 2;
        Some(geometry)
    }
    /// 0 initial, 1 core unsealed, 2 voss captured (exit opened).
    pub fn m17_stage(&self) -> u8 {
        match self {
            Self::Authored(map) if map.m17.is_some() => map.m17_stage,
            _ => 0,
        }
    }
    pub fn prepared_m17_world(&self, stage: u8) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m17.as_ref()?;
        let mut selected = map.as_ref().clone();
        match stage {
            0 => {
                selected.arena = prepared.sealed.clone();
                selected.navigation = prepared.navigation.clone();
            }
            1 => {
                selected.arena = prepared.unsealed.clone();
                selected.navigation = prepared.unsealed_navigation.clone();
            }
            2 => {
                selected.arena = prepared.concluded.clone();
                selected.navigation = prepared.concluded_navigation.clone();
            }
            _ => return None,
        }
        selected.m17_stage = stage;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub(crate) fn m16_objectives(&self) -> Option<&super::authored::m16::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m16.as_deref(),
        }
    }
    pub fn m16_geometry(&self) -> Option<crate::protocol::M16MapGeometry> {
        let mut geometry = self.m16_objectives()?.geometry.clone();
        let stage = self.m16_stage();
        geometry.checkpoint_lifted = stage >= 1;
        geometry.doors_open = stage >= 2;
        Some(geometry)
    }
    /// 0 initial, 1 checkpoint lifted, 2 chamber doors open.
    pub fn m16_stage(&self) -> u8 {
        match self {
            Self::Authored(map) if map.m16.is_some() => map.m16_stage,
            _ => 0,
        }
    }
    pub fn prepared_m16_world(&self, stage: u8) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m16.as_ref()?;
        let mut selected = map.as_ref().clone();
        selected.presentation = prepared.presentation.clone();
        for panel in &mut selected.presentation.decorations {
            if stage >= 1 && panel.solid == prepared.checkpoint_barrier
                || stage >= 2 && panel.solid == prepared.chamber_doors
            {
                panel.face = crate::protocol::MapFace::Up;
                panel.center = [0.0; 2];
            }
        }
        match stage {
            0 => {
                selected.arena = prepared.initial.clone();
                selected.navigation = prepared.navigation.clone();
            }
            1 => {
                selected.arena = prepared.lifted.clone();
                selected.navigation = prepared.lifted_navigation.clone();
            }
            2 => {
                selected.arena = prepared.open.clone();
                selected.navigation = prepared.open_navigation.clone();
            }
            _ => return None,
        }
        selected.m16_stage = stage;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub(crate) fn m15_objectives(&self) -> Option<&super::authored::m15::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m15.as_deref(),
        }
    }
    pub fn m15_geometry(&self) -> Option<crate::protocol::M15MapGeometry> {
        let mut geometry = self.m15_objectives()?.geometry.clone();
        let stage = self.m15_stage();
        geometry.tunnel_closed = stage >= 1;
        geometry.gates_open = stage >= 2;
        Some(geometry)
    }
    /// 0 initial, 1 sealed, 2 released.
    pub fn m15_stage(&self) -> u8 {
        match self {
            Self::Authored(map) if map.m15.is_some() => map.m15_stage,
            _ => 0,
        }
    }
    pub fn prepared_m15_world(&self, stage: u8) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m15.as_ref()?;
        let mut selected = map.as_ref().clone();
        match stage {
            0 => {
                selected.arena.solids[prepared.tunnel_gate] = Solid {
                    min_x: -4.0,
                    bottom: 2.1,
                    min_z: -12.4,
                    max_x: 4.0,
                    top: 2.2,
                    max_z: -11.6,
                };
                selected.navigation = prepared.navigation.clone();
            }
            1 => {
                selected.arena = prepared.sealed.clone();
                selected.navigation = prepared.sealed_navigation.clone();
            }
            2 => {
                selected.arena = prepared.released.clone();
                selected.navigation = prepared.released_navigation.clone();
            }
            _ => return None,
        }
        selected.m15_stage = stage;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub(crate) fn m14_objectives(&self) -> Option<&super::authored::m14::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m14.as_deref(),
        }
    }
    pub fn m14_geometry(&self) -> Option<crate::protocol::M14MapGeometry> {
        let mut g = self.m14_objectives()?.geometry.clone();
        g.fallen = matches!(self,Self::Authored(map) if map.m14_fallen);
        Some(g)
    }
    pub fn prepared_m14_world(&self, feet: [f32; 3]) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let p = map.m14.as_ref()?;
        let mut selected = map.as_ref().clone();
        for (slot, &index) in p.geometry.walker_solids.iter().enumerate() {
            let s = p.fallen[slot];
            let dx = feet[0] - p.origin[0];
            let dz = feet[2] - p.origin[2];
            selected.arena.solids[index] = Solid {
                min_x: s.min_x + dx,
                max_x: s.max_x + dx,
                min_z: s.min_z + dz,
                max_z: s.max_z + dz,
                ..s
            };
        }
        selected.navigation = p.fallen_navigation.clone();
        selected.walker = None;
        selected.m14_fallen = true;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub fn walker_geometry(&self) -> Option<crate::protocol::WalkerGeometry> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.walker.as_ref().map(|p| p.geometry.clone()),
        }
    }
    pub fn m13_geometry(&self) -> Option<crate::protocol::M13MapGeometry> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m13.as_ref()?.geometry.clone(),
        }
    }
    pub(crate) fn m13_gates(&self) -> Option<&crate::mission::m13::Gates> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m13.as_deref().map(|prepared| &prepared.gates),
        }
    }

    pub(crate) fn m12_objectives(&self) -> Option<&super::authored::m12::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m12.as_deref(),
        }
    }
    pub fn m12_geometry(&self) -> Option<crate::protocol::M12MapGeometry> {
        let mut g = self.m12_objectives()?.geometry.clone();
        g.shelter_open = matches!(self,Self::Authored(map) if map.shelter_open);
        Some(g)
    }
    pub fn m12_encounter_index(&self, step: usize) -> Option<usize> {
        self.m12_objectives()?;
        super::authored::m12::OBJECTIVE_GROUPS.get(step).copied()
    }
    pub fn prepared_m12_world(&self) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let p = map.m12.as_ref()?;
        let mut selected = map.as_ref().clone();
        selected.arena = p.opened.clone();
        selected.navigation = p.opened_navigation.clone();
        selected.shelter_open = true;
        Some(Self::Authored(Arc::new(selected)))
    }
    pub(crate) fn m11_objectives(&self) -> Option<&super::authored::m11::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m11.as_deref(),
        }
    }

    pub fn m11_geometry(&self) -> Option<crate::protocol::M11MapGeometry> {
        self.m11_objectives().map(|p| p.geometry.clone())
    }

    pub(crate) fn m10_objectives(&self) -> Option<&super::authored::m10::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m10.as_deref(),
        }
    }
    pub fn m10_geometry(&self) -> Option<crate::protocol::M10MapGeometry> {
        self.m10_objectives().map(|p| p.geometry.clone())
    }

    pub(crate) fn m09_objectives(&self) -> Option<&super::authored::m09::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m09.as_deref(),
        }
    }

    pub fn m09_geometry(&self) -> Option<crate::protocol::M09MapGeometry> {
        let mut geometry = self.m09_objectives()?.geometry.clone();
        geometry.hatch_open = matches!(self, Self::Authored(map) if map.hatch_open);
        Some(geometry)
    }

    /// Authoritative ordered group bound for the berth mission controller.
    pub fn m09_encounter_index(&self, step: usize) -> Option<usize> {
        self.m09_objectives()?.encounters.get(step).copied()
    }

    pub fn prepared_m09_world(&self) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m09.as_ref()?;
        let mut selected = map.as_ref().clone();
        selected.arena = prepared.opened.clone();
        selected.navigation = prepared.opened_navigation.clone();
        selected.hatch_open = true;
        Some(Self::Authored(Arc::new(selected)))
    }

    pub(crate) fn m08_objectives(&self) -> Option<&super::authored::m08::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m08.as_deref(),
        }
    }
    /// Static archive contract with this world's stage flags.
    pub fn m08_geometry(&self) -> Option<crate::protocol::M08MapGeometry> {
        let mut geometry = self.m08_objectives()?.geometry.clone();
        let stage = self.m08_stage();
        geometry.seal_open = stage >= 1;
        geometry.machine_fallen = stage >= 2;
        Some(geometry)
    }
    /// 0 sealed, 1 seal lifted, 2 machine fallen.
    pub fn m08_stage(&self) -> u8 {
        match self {
            Self::Authored(map) if map.m08.is_some() => map.m08_stage,
            _ => 0,
        }
    }
    /// Select a stage precomputed and route-checked at load time. Nothing is
    /// built on a live transition.
    pub fn prepared_m08_world(&self, stage: u8) -> Option<Self> {
        let Self::Authored(map) = self else {
            return None;
        };
        let prepared = map.m08.as_ref()?;
        let mut selected = map.as_ref().clone();
        match stage {
            1 => {
                selected.arena = prepared.opened.clone();
                selected.navigation = prepared.opened_navigation.clone();
            }
            2 => {
                selected.arena = prepared.fallen.clone();
                selected.navigation = prepared.fallen_navigation.clone();
            }
            _ => return None,
        }
        selected.m08_stage = stage;
        for panel in &mut selected.presentation.decorations {
            if panel.kind == crate::protocol::MapDecorationKind::M08SealLocked {
                panel.kind = crate::protocol::MapDecorationKind::M08SealOpen;
            }
        }
        Some(Self::Authored(Arc::new(selected)))
    }
    pub(crate) fn m07_objectives(&self) -> Option<&super::authored::m07::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m07.as_deref(),
        }
    }
    pub fn m07_geometry(&self) -> Option<crate::protocol::M07MapGeometry> {
        self.m07_objectives().map(|p| p.geometry.clone())
    }
    pub(crate) fn m06_objectives(&self) -> Option<&super::authored::m06::Prepared> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.m06.as_deref(),
        }
    }
    pub fn m06_geometry(&self) -> Option<crate::protocol::M06MapGeometry> {
        self.m06_objectives().map(|p| p.geometry.clone())
    }
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
        self.epilogue_objectives()
            .map(|_| crate::protocol::MissionId::StillHere)
            .or_else(|| {
                self.m20_objectives()
                    .map(|_| crate::protocol::MissionId::LocalException)
            })
            .or_else(|| {
                self.m19_objectives()
                    .map(|_| crate::protocol::MissionId::PlannedWorks)
            })
            .or_else(|| {
                self.m18_geometry()
                    .map(|_| crate::protocol::MissionId::AllSystemsNormal)
            })
            .or_else(|| {
                self.m17_geometry()
                    .map(|_| crate::protocol::MissionId::PeaceWithoutInterruption)
            })
            .or_else(|| {
                self.m16_geometry()
                    .map(|_| crate::protocol::MissionId::FreedomOfMovement)
            })
            .or_else(|| {
                self.m15_geometry()
                    .map(|_| crate::protocol::MissionId::CivicPressureValve)
            })
            .or_else(|| {
                self.m14_geometry()
                    .map(|_| crate::protocol::MissionId::LaunchAuthority)
            })
            .or_else(|| {
                self.m13_geometry()
                    .map(|_| crate::protocol::MissionId::WeightOfPermission)
            })
            .or_else(|| {
                self.m12_objectives()
                    .map(|_| crate::protocol::MissionId::TermsOfCooperation)
            })
            .or_else(|| {
                self.m11_objectives()
                    .map(|_| crate::protocol::MissionId::RightOfSearch)
            })
            .or_else(|| {
                self.m10_objectives()
                    .map(|_| crate::protocol::MissionId::CommonCarrier)
            })
            .or_else(|| self.mission().map(|mission| mission.id))
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
            .or_else(|| {
                self.m06_objectives()
                    .map(|_| crate::protocol::MissionId::PortOfEntry)
            })
            .or_else(|| {
                self.m08_objectives()
                    .map(|_| crate::protocol::MissionId::CustodianOfRecord)
            })
            .or_else(|| {
                self.m07_objectives()
                    .map(|_| crate::protocol::MissionId::DeclaredGoods)
            })
            .or_else(|| {
                self.m09_objectives()
                    .map(|_| crate::protocol::MissionId::PassengerManifest)
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
            || self.walker_geometry().is_some()
            || self.mission().is_some()
            || matches!(self, Self::Authored(map) if map.m02.is_some() || map.m03.is_some() || map.m04.is_some() || map.m05.is_some() || map.m06.is_some() || map.m07.is_some() || map.m08.is_some() || map.epilogue.is_some())
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

    /// Content that needs the custody capability: a placed Auditor or a
    /// proximity mine supply.
    pub fn has_custody_devices(&self) -> bool {
        self.encounters().iter().any(|encounter| {
            encounter
                .enemies
                .iter()
                .any(|enemy| enemy.kind == crate::protocol::EnemyKind::Auditor)
        }) || matches!(self, Self::Authored(map) if map.supplies.iter().any(|supply| matches!(supply.kind, crate::sim::PickupKind::ProximityMine { .. })))
    }

    /// A found Sniper Rifle or a Ranged Sweeper needs a client that can read
    /// the `sniper` weapon id and the `ranged_sweeper` actor kind.
    pub fn requires_sniper_contract(&self) -> bool {
        self.encounters().iter().any(|encounter| {
            encounter
                .enemies
                .iter()
                .any(|enemy| enemy.kind == crate::protocol::EnemyKind::RangedSweeper)
        }) || self.pickups().iter().any(|pickup| {
            pickup.kind == crate::sim::PickupKind::Weapon(crate::protocol::WeaponType::Sniper)
        })
    }
    pub fn requires_repeater_contract(&self) -> bool {
        self.pickups().iter().any(|pickup| {
            pickup.kind == crate::sim::PickupKind::Weapon(crate::protocol::WeaponType::Repeater)
        })
    }

    /// Every role must understand the new Cells weapon and nine-column records.
    pub fn requires_arc_contract(&self) -> bool {
        self.pickups().iter().any(|pickup| {
            pickup.kind == crate::sim::PickupKind::Weapon(crate::protocol::WeaponType::Arc)
        })
    }

    pub fn requires_assessor_contract(&self) -> bool {
        self.encounters().iter().any(|group| {
            group
                .enemies
                .iter()
                .any(|enemy| enemy.kind == crate::protocol::EnemyKind::Assessor)
        })
    }

    pub fn requires_m10_contract(&self) -> bool {
        self.m10_objectives().is_some()
            || self
                .presentation_ref()
                .is_some_and(|p| p.decorations.iter().any(|d| d.kind.is_m10()))
    }

    pub fn requires_m11_contract(&self) -> bool {
        self.presentation_ref()
            .is_some_and(|p| p.decorations.iter().any(|d| d.kind.is_m11()))
            || self.encounters().iter().any(|group| {
                group
                    .enemies
                    .iter()
                    .any(|enemy| enemy.kind == crate::protocol::EnemyKind::Redactor)
            })
            || self
                .pickups()
                .iter()
                .any(|pickup| matches!(pickup.kind, crate::sim::PickupKind::RemoteMine { .. }))
    }

    pub fn requires_enforcer_contract(&self) -> bool {
        self.encounters().iter().any(|group| {
            group
                .enemies
                .iter()
                .any(|enemy| enemy.kind == crate::protocol::EnemyKind::Enforcer)
        })
    }

    pub fn equipment_policy(&self) -> crate::protocol::EquipmentPolicy {
        match self {
            Self::BuiltIn(_) => crate::protocol::EquipmentPolicy::FullArsenal,
            Self::Authored(map) => map.equipment,
        }
    }

    pub fn has_authored_vehicles(&self) -> bool {
        self.m16_geometry().is_some()
            || self.m14_geometry().is_some()
            || matches!(self, Self::Authored(map) if !map.vehicles.is_empty())
    }

    pub(crate) fn vehicle_spawns(&self) -> Vec<(crate::protocol::VehicleKind, [f32; 3], f32)> {
        if let Some(g) = self.m16_geometry() {
            return vec![(
                crate::protocol::VehicleKind::Motorcycle,
                g.motorcycle.feet,
                g.motorcycle.yaw,
            )];
        }
        if let Some(g) = self.m14_geometry() {
            return vec![(crate::protocol::VehicleKind::Jeep, g.jeep.feet, g.jeep.yaw)];
        }
        match self {
            Self::BuiltIn(kind) => crate::vehicles::spawns(kind.id()),
            Self::Authored(map) => map
                .vehicles
                .iter()
                .map(|p| (crate::protocol::VehicleKind::Jeep, p.feet, p.yaw))
                .collect(),
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

    pub fn water_regions(&self) -> &[crate::protocol::WaterRegion] {
        match self {
            Self::BuiltIn(crate::sim::MapKind::HoldfastAtoll) => &super::holdfast::WATER,
            _ => &[],
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
            Self::BuiltIn(MapKind::LowWater) => Some(super::low_water::presentation()),
            Self::BuiltIn(MapKind::ArenaDuel) => Some(super::larak_lot::presentation()),
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

    pub(crate) fn sabotage_layout(&self) -> Option<&'static super::SabotageLayout> {
        match self {
            Self::BuiltIn(kind) => super::sabotage_layout(*kind),
            Self::Authored(_) => None,
        }
    }

    /// The extra weapon pads a free-for-all lays on this map. None on an
    /// authored map, which places its own supplies.
    pub(crate) fn scrap_pads(&self) -> Vec<ArenaPickup> {
        match self {
            Self::BuiltIn(kind) => kind.scrap_pads(),
            Self::Authored(_) => Vec::new(),
        }
    }

    pub(crate) fn pickups(&self) -> Vec<ArenaPickup> {
        match self {
            Self::BuiltIn(kind) => kind.pickups(),
            Self::Authored(map) => {
                let mut supplies = map.supplies.clone();
                if map.m12.is_some() {
                    for supply in &mut supplies {
                        if super::authored::m12::AID_SUPPLY_IDS.contains(&supply.id.as_str()) {
                            supply.available = false;
                        }
                    }
                }
                supplies
            }
        }
    }

    pub(crate) fn is_m12_aid_supply(&self, id: &str) -> bool {
        self.m12_objectives().is_some() && super::authored::m12::AID_SUPPLY_IDS.contains(&id)
    }

    pub(crate) fn spawn_slots(&self) -> usize {
        match self {
            Self::BuiltIn(MapKind::HoldfastAtoll) => 16,
            Self::BuiltIn(MapKind::ArenaDuel) => super::larak_lot::SPAWNS.len(),
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
                (
                    spawn.feet[0],
                    spawn.feet[2],
                    crate::movement::normalize_yaw(spawn.yaw),
                    spawn.feet[1],
                )
            }
        }
    }

    pub fn article_blade_info(&self) -> Option<crate::protocol::ArticleBladeInfo> {
        match self {
            Self::BuiltIn(_) => None,
            Self::Authored(map) => map.article_blade(),
        }
    }

    pub fn requires_article_blade_contract(&self) -> bool {
        self.article_blade_info().is_some()
    }
}
