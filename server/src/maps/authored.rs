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
mod mission;
mod supplies;

const MAX_BYTES: u64 = 1_048_576;
const MAX_PLACEMENTS: usize = 128;

#[cfg(test)]
mod encounters_tests;
#[cfg(test)]
mod m02_tests;
#[cfg(test)]
mod tests;

#[derive(Debug, Clone)]
pub struct AuthoredMap {
    pub(super) content_sha256: [u8; 32],
    pub(super) mission: Option<crate::protocol::MissionGeometry>,
    pub(super) opened_route: Option<Arc<Self>>,
    pub(super) m02: Option<Arc<m02::Prepared>>,
    pub(super) id: u32,
    pub(super) name: String,
    pub(super) arena: Arena,
    pub(super) navigation: Arc<Navigation>,
    pub(super) spawns: Vec<Placement>,
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
            || doc.decorations.len() > crate::protocol::MAX_MAP_DECORATIONS
        {
            return Err(invalid("map requires bounded solids, spawns and landmarks"));
        }
        let mut seen = HashSet::new();
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
        let mission = doc
            .mission
            .map(|definition| definition.prepare(&arena, &solid_ids, &mut presentation))
            .transpose()?;
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
        let m02 = doc
            .m02
            .map(|definition| {
                definition.prepare(&arena, &solid_ids, &mut presentation, start, &mut seen)
            })
            .transpose()?
            .map(Arc::new);
        let supplies = supplies::build(doc.supplies, doc.equipment, &arena, &mut seen)?;
        encounters::validate(&doc.encounters, doc.equipment, &arena, &mut seen)?;
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        let opened_navigation = mission
            .as_ref()
            .map(|m| Navigation::shared(m.opened.clone()).map_err(invalid))
            .transpose()?;
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
            .chain(
                doc.encounters
                    .iter()
                    .flat_map(|e| e.enemies.iter().map(|p| (p.id.as_str(), p.feet))),
            )
        {
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
            encounters: doc.encounters,
            supplies,
            equipment: doc.equipment,
            id: doc.map_id,
            name: doc.name,
            arena,
            navigation,
            spawns: doc.spawns,
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
