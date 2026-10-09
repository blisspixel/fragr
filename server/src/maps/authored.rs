//! Strict local authoring boundary. Wire compatibility belongs to protocol.rs.

use crate::movement::{Arena, Solid, BODY_HEIGHT, CONTACT_EPSILON, RADIUS};
use crate::navigation::Navigation;
use crate::protocol::{MapDecoration, MapPresentation, MapSurface};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::io::{self, Read};
use std::path::Path;
use std::sync::Arc;

pub(crate) mod encounters;
pub(crate) mod m02;
pub(crate) mod m03;
pub(crate) mod m04;
pub(crate) mod m05;
pub(crate) mod m06;
pub(crate) mod m07;
pub(crate) mod m08;
pub(crate) mod m09;
pub(crate) mod m10;
pub(crate) mod m11;
pub(crate) mod m12;
mod mission;
mod supplies;
mod vehicle_placements;

const MAX_BYTES: u64 = 1_048_576;
const MAX_PLACEMENTS: usize = 128;

#[cfg(test)]
mod encounters_tests;
#[cfg(test)]
mod m02_tests;
#[cfg(test)]
mod m09_tests;
#[cfg(test)]
mod m10_geometry_tests;
#[cfg(test)]
mod m11_geometry_tests;
#[cfg(test)]
mod tests;

#[derive(Debug, Clone)]
pub struct AuthoredMap {
    pub(super) content_sha256: [u8; 32],
    pub(super) mission: Option<crate::protocol::MissionGeometry>,
    pub(super) opened_route: Option<Arc<Self>>,
    pub(super) m02: Option<Arc<m02::Prepared>>,
    pub(super) m03: Option<Arc<m03::Prepared>>,
    pub(super) m04: Option<Arc<m04::Prepared>>,
    pub(super) m05: Option<Arc<m05::Prepared>>,
    pub(super) m06: Option<Arc<m06::Prepared>>,
    pub(super) m08: Option<Arc<m08::Prepared>>,
    pub(super) m09: Option<Arc<m09::Prepared>>,
    pub(super) m10: Option<Arc<m10::Prepared>>,
    pub(super) m11: Option<Arc<m11::Prepared>>,
    pub(super) m12: Option<Arc<m12::Prepared>>,
    pub(super) shelter_open: bool,
    pub(super) hatch_open: bool,
    /// M08 runtime stage: 0 sealed, 1 seal lifted, 2 machine fallen.
    pub(super) m08_stage: u8,
    pub(super) m07: Option<Arc<m07::Prepared>>,
    pub(super) freight_open: bool,
    pub(super) clinic_open: bool,
    pub(super) mast_shutdown: bool,
    pub(super) id: u32,
    pub(super) name: String,
    pub(super) arena: Arena,
    pub(super) navigation: Arc<Navigation>,
    pub(super) spawns: Vec<Placement>,
    pub(super) vehicles: Vec<Placement>,
    pub(super) presentation: MapPresentation,
    pub(super) equipment: crate::protocol::EquipmentPolicy,
    pub(super) supplies: Vec<crate::sim::ArenaPickup>,
    pub(super) encounters: Vec<encounters::EncounterDefinition>,
    landmarks: Vec<Landmark>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Document {
    #[serde(default)]
    mission: Option<mission::Definition>,
    #[serde(default)]
    m02: Option<m02::Definition>,
    #[serde(default)]
    m03: Option<m03::Definition>,
    #[serde(default)]
    m04: Option<m04::Definition>,
    #[serde(default)]
    m05: Option<m05::Definition>,
    #[serde(default)]
    m06: Option<m06::Definition>,
    #[serde(default)]
    m08: Option<m08::Definition>,
    #[serde(default)]
    m09: Option<m09::Definition>,
    m07: Option<m07::Definition>,
    #[serde(default)]
    m10: Option<m10::Definition>,
    #[serde(default)]
    m11: Option<m11::Definition>,
    #[serde(default)]
    m12: Option<m12::Definition>,
    #[serde(default)]
    decorations: Vec<MapDecoration<String>>,
    #[serde(default)]
    encounters: Vec<encounters::EncounterDefinition>,
    #[serde(default)]
    supplies: Vec<supplies::Definition>,
    #[serde(default)]
    equipment: crate::protocol::EquipmentPolicy,
    version: u32,
    map_id: u32,
    name: String,
    half_extent: f32,
    ground: MapSurface,
    solids: Vec<Volume>,
    spawns: Vec<Placement>,
    #[serde(default)]
    vehicles: Vec<Placement>,
    landmarks: Vec<Landmark>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Volume {
    id: String,
    min: [f32; 3],
    max: [f32; 3],
    surface: MapSurface,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Placement {
    id: String,
    pub feet: [f32; 3],
    pub yaw: f32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct Landmark {
    id: String,
    feet: [f32; 3],
}

fn invalid(reason: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, reason)
}

fn identity(id: &str, seen: &mut HashSet<String>) -> io::Result<()> {
    if id.is_empty()
        || id.len() > 64
        || !id
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
        || !seen.insert(id.to_owned())
    {
        return Err(invalid(
            "map identifiers must be unique lowercase ASCII names, at most 64 bytes",
        ));
    }
    Ok(())
}

fn standing(arena: &Arena, feet: [f32; 3]) -> bool {
    let [x, y, z] = feet;
    feet.iter().all(|v| v.is_finite())
        && x.abs() <= arena.half - RADIUS
        && z.abs() <= arena.half - RADIUS
        && y >= 0.0
        && y + BODY_HEIGHT <= crate::movement::MAX_HALF_EXTENT * 2.0
        && !arena.blocked_body_at(x, z, y, y)
        && [-RADIUS, RADIUS].into_iter().all(|dx| {
            [-RADIUS, RADIUS].into_iter().all(|dz| {
                (arena.support_height(x + dx, z + dz, y + CONTACT_EPSILON) - y).abs()
                    <= CONTACT_EPSILON
            })
        })
}

impl AuthoredMap {
    /// Bound bytes before JSON allocation and topology work. No paths or URLs
    /// inside a map can load additional content.
    pub fn load(path: &Path) -> io::Result<Arc<Self>> {
        Self::read(std::fs::File::open(path)?)
    }

    pub fn read(reader: impl Read) -> io::Result<Arc<Self>> {
        let mut bytes = Vec::new();
        reader.take(MAX_BYTES + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_BYTES {
            return Err(invalid("map file exceeds the 1 MiB limit"));
        }
        let content_sha256 = Sha256::digest(&bytes).into();
        // Parser errors can include untrusted field values. Report location,
        // not the file's contents, in host diagnostics.
        let doc: Document = serde_json::from_slice(&bytes).map_err(|error| {
            invalid(&format!(
                "invalid map document at line {}, column {}",
                error.line(),
                error.column()
            ))
        })?;
        if doc.version != 1 {
            return Err(invalid("unsupported map document version"));
        }
        // Keep the numeric arcade roster's identities reserved.
        if doc.map_id < 1000
            || doc.name.trim().is_empty()
            || doc.name.chars().count() > 80
            || doc.name.chars().any(char::is_control)
        {
            return Err(invalid("invalid authored map identity or name"));
        }
        if doc.solids.len() > crate::movement::MAX_SOLIDS
            || doc.spawns.is_empty()
            || doc.spawns.len() > MAX_PLACEMENTS
            || doc.landmarks.is_empty()
            || doc.landmarks.len() > MAX_PLACEMENTS
            || doc.supplies.len() > MAX_PLACEMENTS
            || doc.vehicles.len() > crate::protocol::MAX_VEHICLES
            || doc.decorations.len() > crate::protocol::MAX_MAP_DECORATIONS
        {
            return Err(invalid("map requires bounded solids, spawns and landmarks"));
        }
        let mut seen = HashSet::new();
        // A parked fleet must be checked against every possible collision
        // world. The first authored fleet is deliberately static-only.
        if !doc.vehicles.is_empty()
            && [
                doc.mission.is_some(),
                doc.m02.is_some(),
                doc.m03.is_some(),
                doc.m04.is_some(),
                doc.m05.is_some(),
                doc.m06.is_some(),
                doc.m07.is_some(),
                doc.m08.is_some(),
                doc.m09.is_some(),
                doc.m10.is_some(),
                doc.m11.is_some(),
                doc.m12.is_some(),
            ]
            .into_iter()
            .any(|v| v)
        {
            return Err(invalid(
                "authored vehicles require a static development world",
            ));
        }
        let mut solids = Vec::with_capacity(doc.solids.len());
        let mut surfaces = Vec::with_capacity(doc.solids.len());
        let mut solid_ids = std::collections::HashMap::with_capacity(doc.solids.len());
        for volume in doc.solids {
            identity(&volume.id, &mut seen)?;
            solid_ids.insert(volume.id, solids.len());
            surfaces.push(volume.surface);
            solids.push(Solid {
                min_x: volume.min[0],
                max_x: volume.max[0],
                bottom: volume.min[1],
                top: volume.max[1],
                min_z: volume.min[2],
                max_z: volume.max[2],
            });
        }
        crate::movement::validate_geometry(doc.half_extent, &solids).map_err(invalid)?;
        let decorations = doc
            .decorations
            .into_iter()
            .map(|detail| {
                let index = solid_ids
                    .get(&detail.solid)
                    .copied()
                    .ok_or_else(|| invalid("map decoration references an unknown solid"))?;
                // A signal lamp must mean one gate's real state, so only a gate places it.
                if matches!(
                    detail.kind,
                    crate::protocol::MapDecorationKind::GateLocked
                        | crate::protocol::MapDecorationKind::GateOpen
                ) {
                    return Err(invalid("gate signals belong to an M02 gate"));
                }
                Ok(detail.with_solid(index))
            })
            .collect::<io::Result<Vec<_>>>()?;
        crate::protocol::validate_decorations(&decorations, &solids).map_err(invalid)?;
        let arena = Arena {
            half: doc.half_extent,
            solids,
        };
        let mut presentation = MapPresentation {
            ground: doc.ground,
            solids: surfaces,
            decorations,
        };
        if doc.m03.is_none()
            && presentation.decorations.iter().any(|panel| {
                matches!(
                    panel.kind,
                    crate::protocol::MapDecorationKind::M03ScheduleBoard
                        | crate::protocol::MapDecorationKind::M03ScheduleCancelled
                        | crate::protocol::MapDecorationKind::M03PlatformCar
                        | crate::protocol::MapDecorationKind::M03SidingCar
                        | crate::protocol::MapDecorationKind::M03RoofCar
                        | crate::protocol::MapDecorationKind::M03MastSign
                        | crate::protocol::MapDecorationKind::M03BoardTrain
                )
            })
        {
            return Err(invalid("M03 registered panels require Scheduled Service"));
        }
        if doc.m04.is_none()
            && presentation.decorations.iter().any(|p| {
                matches!(
                    p.kind,
                    crate::protocol::MapDecorationKind::M04ClinicCare
                        | crate::protocol::MapDecorationKind::M04ClinicSign
                        | crate::protocol::MapDecorationKind::M04FieldPrinter
                        | crate::protocol::MapDecorationKind::M04MarketCanvas
                        | crate::protocol::MapDecorationKind::M04MealSix
                        | crate::protocol::MapDecorationKind::M04NoodleSix
                        | crate::protocol::MapDecorationKind::M04NoticeBoard
                        | crate::protocol::MapDecorationKind::M04PaintLocker
                        | crate::protocol::MapDecorationKind::M04RepairBench
                        | crate::protocol::MapDecorationKind::M04TramVote
                        | crate::protocol::MapDecorationKind::M04WaterTank
                        | crate::protocol::MapDecorationKind::M04Workshop
                        | crate::protocol::MapDecorationKind::M04ClinicControl
                        | crate::protocol::MapDecorationKind::M04RoofDeparture
                )
            })
        {
            return Err(invalid("M04 registered panels require Notice to Vacate"));
        }
        if doc.m05.is_none()
            && presentation.decorations.iter().any(|p| {
                matches!(
                    p.kind,
                    crate::protocol::MapDecorationKind::M05WaterTank
                        | crate::protocol::MapDecorationKind::M05PaintBench
                        | crate::protocol::MapDecorationKind::M05LoadingPen
                        | crate::protocol::MapDecorationKind::M05TramService
                        | crate::protocol::MapDecorationKind::M05MarketSix
                        | crate::protocol::MapDecorationKind::M05FreightSign
                        | crate::protocol::MapDecorationKind::M05ShipDeparture
                )
            })
        {
            return Err(invalid(
                "M05 registered panels require No Forwarding Address",
            ));
        }
        if presentation
            .decorations
            .iter()
            .any(|panel| panel.kind == crate::protocol::MapDecorationKind::M03ScheduleCancelled)
        {
            return Err(invalid(
                "M03 cancellation belongs to the fallen runtime world",
            ));
        }
        // Ballistic pressure windows belong to the registered glass missions.
        if presentation.ground == MapSurface::InspectionGlass
            || (doc.m02.is_none()
                && doc.m06.is_none()
                && doc.m07.is_none()
                && doc.m09.is_none()
                && doc.m10.is_none()
                && doc.m11.is_none()
                && presentation.solids.contains(&MapSurface::InspectionGlass))
        {
            return Err(invalid(
                "inspection glass belongs to an M02, M06, M07, M09, M10 or M11 solid",
            ));
        }
        if doc.m07.is_none() && presentation.decorations.iter().any(|p| p.kind.is_m07()) {
            return Err(invalid("M07 registered panels require Declared Goods"));
        }
        if doc.m06.is_none()
            && presentation.decorations.iter().any(|p| {
                matches!(
                    p.kind,
                    crate::protocol::MapDecorationKind::M06DustDeclaration
                        | crate::protocol::MapDecorationKind::M06RailConfiscation
                        | crate::protocol::MapDecorationKind::M06FreightGantry
                        | crate::protocol::MapDecorationKind::M06FamilyWindow
                        | crate::protocol::MapDecorationKind::M06ServiceSix
                        | crate::protocol::MapDecorationKind::M06CraneOverlook
                        | crate::protocol::MapDecorationKind::M06DutyFreeSix
                        | crate::protocol::MapDecorationKind::M06ImpoundObservation
                        | crate::protocol::MapDecorationKind::M06DepotOverlook
                        | crate::protocol::MapDecorationKind::M06TransitDeparture
                )
            })
        {
            return Err(invalid("M06 registered panels require Port of Entry"));
        }
        let m08_kind = |kind: crate::protocol::MapDecorationKind| {
            use crate::protocol::MapDecorationKind as K;
            matches!(
                kind,
                K::M08CheckpointForm
                    | K::M08ObservationSix
                    | K::M08LostPropertySix
                    | K::M08Registry
                    | K::M08BayRelease
                    | K::M08BayForm
                    | K::M08MineCage
                    | K::M08SealLocked
                    | K::M08SealOpen
                    | K::M08ServiceSix
                    | K::M08ColdCabinet
                    | K::M08EvidenceDesk
                    | K::M08AuthorizedNoise
                    | K::M08FreightDeparture
                    | K::M08CustodyShaft
            )
        };
        if doc.m08.is_none() && presentation.decorations.iter().any(|p| m08_kind(p.kind)) {
            return Err(invalid("M08 registered panels require Custodian of Record"));
        }
        // The open seal signal belongs to the lifted runtime stages.
        if presentation
            .decorations
            .iter()
            .any(|p| p.kind == crate::protocol::MapDecorationKind::M08SealOpen)
        {
            return Err(invalid("M08 open seal belongs to a lifted runtime stage"));
        }
        if doc.mission.is_some() && doc.equipment != crate::protocol::EquipmentPolicy::Discovery {
            return Err(invalid("missions require discovered equipment"));
        }
        if doc.m02.is_some()
            && (doc.mission.is_some()
                || doc.map_id != 1002
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery)
        {
            return Err(invalid(
                "M02 objectives require map 1002, discovery equipment and no M01 mission",
            ));
        }
        if doc.m03.is_some()
            && (doc.mission.is_some()
                || doc.m02.is_some()
                || doc.map_id != 1003
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery)
        {
            return Err(invalid(
                "M03 requires map 1003, discovered equipment and no other mission",
            ));
        }
        if doc.m04.is_some()
            && (doc.mission.is_some()
                || doc.m02.is_some()
                || doc.m03.is_some()
                || doc.map_id != 1004
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery)
        {
            return Err(invalid(
                "M04 requires map 1004, discovery and no other mission",
            ));
        }
        if doc.m09.is_some()
            && (doc.mission.is_some()
                || doc.m02.is_some()
                || doc.m03.is_some()
                || doc.m04.is_some()
                || doc.m05.is_some()
                || doc.m06.is_some()
                || doc.m07.is_some()
                || doc.m08.is_some()
                || doc.map_id != 1009
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery)
        {
            return Err(invalid(
                "M09 requires map1009, discovery and no other mission",
            ));
        }
        if doc.m10.is_some()
            && (doc.map_id != 1010
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery
                || doc.mission.is_some()
                || doc.m02.is_some()
                || doc.m03.is_some()
                || doc.m04.is_some()
                || doc.m05.is_some()
                || doc.m06.is_some()
                || doc.m07.is_some()
                || doc.m08.is_some()
                || doc.m09.is_some())
        {
            return Err(invalid(
                "M10 requires map1010, discovery and no other mission",
            ));
        }
        if doc.m11.is_some()
            && (doc.map_id != 1011
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery
                || doc.mission.is_some()
                || doc.m02.is_some()
                || doc.m03.is_some()
                || doc.m04.is_some()
                || doc.m05.is_some()
                || doc.m06.is_some()
                || doc.m07.is_some()
                || doc.m08.is_some()
                || doc.m09.is_some()
                || doc.m10.is_some())
        {
            return Err(invalid(
                "M11 requires map1011, discovery and no other mission",
            ));
        }
        if doc.m11.is_none() && presentation.decorations.iter().any(|p| p.kind.is_m11()) {
            return Err(invalid("M11 registered panels require Right of Search"));
        }
        if doc.m12.is_some()
            && (doc.map_id != 1012
                || doc.name != "Terms of Cooperation"
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery
                || doc.mission.is_some()
                || doc.m02.is_some()
                || doc.m03.is_some()
                || doc.m04.is_some()
                || doc.m05.is_some()
                || doc.m06.is_some()
                || doc.m07.is_some()
                || doc.m08.is_some()
                || doc.m09.is_some()
                || doc.m10.is_some()
                || doc.m11.is_some())
        {
            return Err(invalid(
                "M12 requires canonical map1012, discovery and no other mission",
            ));
        }
        let mission = doc
            .mission
            .map(|definition| definition.prepare(&arena, &solid_ids, &mut presentation))
            .transpose()?;
        if doc.m05.is_some()
            && (mission.is_some()
                || doc.m02.is_some()
                || doc.m03.is_some()
                || doc.m04.is_some()
                || doc.map_id != 1005
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery)
        {
            return Err(invalid(
                "M05 requires map1005, discovery and no other mission",
            ));
        }
        if doc.m06.is_some()
            && (mission.is_some()
                || doc.m02.is_some()
                || doc.m03.is_some()
                || doc.m04.is_some()
                || doc.m05.is_some()
                || doc.m07.is_some()
                || doc.map_id != 1006
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery)
        {
            return Err(invalid(
                "M06 requires map1006, discovery and no other mission",
            ));
        }
        if doc.m08.is_some()
            && (mission.is_some()
                || doc.m02.is_some()
                || doc.m03.is_some()
                || doc.m04.is_some()
                || doc.m05.is_some()
                || doc.m06.is_some()
                || doc.m07.is_some()
                || doc.map_id != 1008
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery)
        {
            return Err(invalid(
                "M08 requires map1008, discovery and no other mission",
            ));
        }
        if doc.m07.is_some()
            && (mission.is_some()
                || doc.m02.is_some()
                || doc.m03.is_some()
                || doc.m04.is_some()
                || doc.m05.is_some()
                || doc.m06.is_some()
                || doc.m08.is_some()
                || doc.map_id != 1007
                || doc.equipment != crate::protocol::EquipmentPolicy::Discovery)
        {
            return Err(invalid(
                "M07 requires map1007, discovery and no other mission",
            ));
        }
        for spawn in &doc.spawns {
            identity(&spawn.id, &mut seen)?;
            if !standing(&arena, spawn.feet)
                || !spawn.yaw.is_finite()
                || !(0.0..std::f32::consts::TAU).contains(&spawn.yaw)
            {
                return Err(invalid(
                    "map spawn needs supported feet, full clearance and bounded yaw",
                ));
            }
        }
        for landmark in &doc.landmarks {
            identity(&landmark.id, &mut seen)?;
            if !standing(&arena, landmark.feet) {
                return Err(invalid(
                    "map landmark needs supported feet and full clearance",
                ));
            }
        }
        let start = doc.spawns[0].feet;
        vehicle_placements::validate(&doc.vehicles, &arena, &mut seen)?;
        let parked_navigation =
            vehicle_placements::boarding_navigation(&doc.vehicles, &arena, start, &doc.encounters)?;
        let m11 = doc
            .m11
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m12 = doc
            .m12
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m10 = doc
            .m10
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m09 = doc
            .m09
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m07 = doc
            .m07
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m08 = doc
            .m08
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m06 = doc
            .m06
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m05 = doc
            .m05
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m04 = doc
            .m04
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m03 = doc
            .m03
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let m02 = doc
            .m02
            .map(|definition| {
                definition.prepare(
                    &arena,
                    &solid_ids,
                    &doc.encounters,
                    &mut presentation,
                    start,
                    &mut seen,
                )
            })
            .transpose()?
            .map(Arc::new);
        let supplies = supplies::build(doc.supplies, doc.equipment, &arena, &mut seen)?;
        if m12.is_some() {
            m12::validate_supplies(&supplies)?;
        }
        encounters::validate(&doc.encounters, doc.equipment, &arena, &mut seen)?;
        let navigation = if let Some(prepared) = &m12 {
            prepared.navigation.clone()
        } else if let Some(prepared) = &m11 {
            prepared.navigation.clone()
        } else if let Some(prepared) = &m10 {
            prepared.navigation.clone()
        } else if let Some(prepared) = &m09 {
            prepared.navigation.clone()
        } else if let Some(prepared) = &m08 {
            prepared.navigation.clone()
        } else if let Some(prepared) = &m07 {
            prepared.navigation.clone()
        } else if let Some(prepared) = &m06 {
            prepared.navigation.clone()
        } else if let Some(prepared) = &m05 {
            prepared.initial_navigation.clone()
        } else if let Some(prepared) = &m04 {
            prepared.initial_navigation.clone()
        } else if let Some(prepared) = &m03 {
            prepared.initial_navigation.clone()
        } else {
            Navigation::shared(arena.clone()).map_err(invalid)?
        };
        if let Some(prepared) = &m03 {
            for destination in doc
                .spawns
                .iter()
                .map(|p| p.feet)
                .chain(doc.landmarks.iter().map(|p| p.feet))
                .chain(supplies.iter().map(|p| [p.x, p.floor, p.z]))
                .chain(
                    doc.encounters
                        .iter()
                        .flat_map(|e| e.enemies.iter().map(|p| p.feet)),
                )
            {
                if !standing(&prepared.fallen, destination)
                    || prepared
                        .navigation
                        .route(start, destination, crate::navigation::SEARCH_LIMIT)
                        .status
                        != crate::navigation::RouteStatus::Complete
                {
                    return Err(invalid("M03 fallen world blocks an authored placement"));
                }
            }
        }
        // The optional M02 room has its own grounded captive route. Check it
        // in the prepared raised-shutter world before admitting a party.
        if doc
            .encounters
            .iter()
            .any(|encounter| encounter.id == "side_ward_guards")
        {
            let released = m02
                .as_ref()
                .and_then(|prepared| prepared.world(1))
                .ok_or_else(|| invalid("M02 side ward requires a released gate world"))?;
            crate::mission::validate_m02_evacuation_route(released.1).map_err(invalid)?;
        }
        let opened_navigation = if let Some(prepared) = &m09 {
            Some(prepared.opened_navigation.clone())
        } else if let Some(prepared) = &m08 {
            Some(prepared.fallen_navigation.clone())
        } else if let Some(prepared) = &m05 {
            Some(prepared.navigation.clone())
        } else if let Some(prepared) = &m04 {
            Some(prepared.navigation.clone())
        } else {
            mission
                .as_ref()
                .map(|m| Navigation::shared(m.opened.clone()).map_err(invalid))
                .transpose()?
        };
        if let (Some(mission), Some(opened)) = (&mission, &opened_navigation) {
            mission.validate_routes(start, &navigation, opened)?;
        }
        for spawn in &doc.spawns {
            if navigation
                .route(start, spawn.feet, crate::navigation::SEARCH_LIMIT)
                .status
                != crate::navigation::RouteStatus::Complete
            {
                return Err(invalid("map spawn is unreachable from the entry"));
            }
            vehicle_placements::reachable(parked_navigation.as_deref(), start, spawn.feet)
                .map_err(|error| invalid(&format!("map placement {}: {error}", spawn.id)))?;
        }
        for (id, destination) in doc
            .landmarks
            .iter()
            .map(|p| (p.id.as_str(), p.feet))
            .chain(
                supplies
                    .iter()
                    .map(|p| (p.id.as_str(), [p.x, p.floor, p.z])),
            )
            .chain(doc.encounters.iter().flat_map(|e| {
                e.enemies.iter().map(|p| {
                    (
                        p.id.as_str(),
                        p.hover.as_ref().map_or(p.feet, |h| h.approach),
                    )
                })
            }))
        {
            vehicle_placements::reachable(parked_navigation.as_deref(), start, destination)
                .map_err(|error| invalid(&format!("map placement {id}: {error}")))?;
            if navigation
                .route(start, destination, crate::navigation::SEARCH_LIMIT)
                .status
                != crate::navigation::RouteStatus::Complete
                && !opened_navigation.as_ref().is_some_and(|opened| {
                    opened
                        .route(start, destination, crate::navigation::SEARCH_LIMIT)
                        .status
                        == crate::navigation::RouteStatus::Complete
                })
                && !m02.as_ref().is_some_and(|prepared| {
                    prepared.navigations().any(|nav| {
                        nav.route(start, destination, crate::navigation::SEARCH_LIMIT)
                            .status
                            == crate::navigation::RouteStatus::Complete
                    })
                })
            {
                return Err(invalid(&format!(
                    "map placement {id} is unreachable from the entry",
                )));
            }
        }
        let mut map = Self {
            content_sha256,
            mission: mission.as_ref().map(|m| m.geometry.clone()),
            opened_route: None,
            m02,
            m03,
            m04,
            m05,
            m06,
            m08,
            m09,
            m10,
            m11,
            m12,
            shelter_open: false,
            hatch_open: false,
            m08_stage: 0,
            m07,
            freight_open: false,
            clinic_open: false,
            mast_shutdown: false,
            encounters: doc.encounters,
            supplies,
            equipment: doc.equipment,
            id: doc.map_id,
            name: doc.name,
            arena,
            navigation,
            spawns: doc.spawns,
            vehicles: doc.vehicles,
            presentation,
            landmarks: doc.landmarks,
        };
        if let (Some(mission), Some(navigation)) = (mission, opened_navigation) {
            let mut opened = map.clone();
            opened.arena = mission.opened;
            opened.navigation = navigation;
            map.opened_route = Some(Arc::new(opened));
        }
        Ok(Arc::new(map))
    }

    pub fn landmark(&self, id: &str) -> Option<[f32; 3]> {
        self.landmarks.iter().find(|p| p.id == id).map(|p| p.feet)
    }
}
