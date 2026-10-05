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
        self.m10_objectives()
            .map(|_| crate::protocol::MissionId::CommonCarrier)
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
            || self.mission().is_some()
            || matches!(self, Self::Authored(map) if map.m02.is_some() || map.m03.is_some() || map.m04.is_some() || map.m05.is_some() || map.m06.is_some() || map.m07.is_some() || map.m08.is_some())
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

    pub(crate) fn sabotage_layout(&self) -> Option<&'static super::SabotageLayout> {
        match self {
            Self::BuiltIn(kind) => super::sabotage_layout(*kind),
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
