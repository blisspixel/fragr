//! Strict local authoring boundary. Wire compatibility belongs to protocol.rs.

use crate::movement::{Arena, Solid, BODY_HEIGHT, CONTACT_EPSILON, RADIUS};
use crate::navigation::Navigation;
use crate::protocol::{MapDecoration, MapPresentation, MapSurface};
use serde::Deserialize;
use std::collections::HashSet;
use std::io::{self, Read};
use std::path::Path;
use std::sync::Arc;

pub(crate) mod encounters;
mod supplies;

const MAX_BYTES: u64 = 1_048_576;
const MAX_PLACEMENTS: usize = 128;

#[cfg(test)]
mod encounters_tests;
#[cfg(test)]
mod tests;

#[derive(Debug)]
pub struct AuthoredMap {
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

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Placement {
    id: String,
    pub feet: [f32; 3],
    pub yaw: f32,
}

#[derive(Debug, Deserialize)]
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
        let supplies = supplies::build(doc.supplies, doc.equipment, &arena, &mut seen)?;
        encounters::validate(&doc.encounters, doc.equipment, &arena, &mut seen)?;
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
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
            if navigation
                .route(start, destination, crate::navigation::SEARCH_LIMIT)
                .status
                != crate::navigation::RouteStatus::Complete
            {
                return Err(invalid("map placement is unreachable from the entry"));
            }
        }
        Ok(Arc::new(Self {
            encounters: doc.encounters,
            supplies,
            equipment: doc.equipment,
            id: doc.map_id,
            name: doc.name,
            arena,
            navigation,
            spawns: doc.spawns,
            presentation: MapPresentation {
                ground: doc.ground,
                solids: surfaces,
                decorations,
            },
            landmarks: doc.landmarks,
        }))
    }

    pub fn landmark(&self, id: &str) -> Option<[f32; 3]> {
        self.landmarks.iter().find(|p| p.id == id).map(|p| p.feet)
    }
}
