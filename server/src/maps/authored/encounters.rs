//! Data-only encounter authoring, validated before navigation or server startup.
use super::{identity, invalid, standing};
use crate::movement::Arena;
pub(crate) use crate::protocol::Region3 as EntryRegion;
use crate::protocol::{EnemyKind, EquipmentPolicy};
use serde::Deserialize;
use std::collections::HashSet;
use std::io;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct EncounterDefinition {
    pub id: String,
    #[serde(default)]
    pub after: Option<String>,
    pub regions: Vec<EntryRegion>,
    pub enemies: Vec<EnemyPlacement>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct EnemyPlacement {
    pub id: String,
    pub kind: EnemyKind,
    pub feet: [f32; 3],
    pub yaw: f32,
    #[serde(default)]
    pub seated: bool,
    #[serde(default)]
    pub hover: Option<Hover>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Hover {
    pub volume: EntryRegion,
    pub band: [f32; 2],
    pub patrol: Vec<[f32; 3]>,
    pub approach: [f32; 3],
}
impl Hover {
    pub(crate) fn validate(&self, arena: &Arena, feet: [f32; 3]) -> io::Result<()> {
        let v = &self.volume;
        if !v.valid(arena.half)
            || !self.band.iter().all(|x| x.is_finite())
            || self.band[0] < 2.5
            || self.band[1] > 8.0
            || self.band[0] >= self.band[1]
            || v.min[1] < self.band[0]
            || v.max[1] > self.band[1]
            || v.min[0] < -arena.half + 0.65
            || v.max[0] > arena.half - 0.65
            || v.min[2] < -arena.half + 0.65
            || v.max[2] > arena.half - 0.65
            || !v.contains(feet)
            || !(2..=8).contains(&self.patrol.len())
            || !standing(arena, self.approach)
            || self
                .patrol
                .iter()
                .any(|p| !p.iter().all(|x| x.is_finite()) || !v.contains(*p))
        {
            return Err(invalid(
                "Notary requires bounded hover, patrol and grounded approach",
            ));
        }
        // An empty expanded volume makes every bounded straight steering segment
        // safe. It is deliberately stricter than a general air path graph.
        if arena.solids.iter().any(|s| {
            s.max_x > v.min[0] - 0.65
                && s.min_x < v.max[0] + 0.65
                && s.max_z > v.min[2] - 0.65
                && s.min_z < v.max[2] + 0.65
                && s.top > v.min[1]
                && s.bottom < v.max[1] + 0.7
        }) {
            return Err(invalid("Notary hover volume clips authoritative cover"));
        }
        let eye = [
            self.approach[0],
            self.approach[1] + crate::movement::EYE_HEIGHT,
            self.approach[2],
        ];
        for p in self.patrol.iter().copied().chain(std::iter::once(feet)) {
            let aim = [p[0], p[1] + 0.35, p[2]];
            let distance = (0..3)
                .map(|i| (eye[i] - aim[i]).powi(2))
                .sum::<f32>()
                .sqrt();
            if distance > crate::protocol::WeaponType::Scatter.range_units()
                || (p[0] - eye[0]).hypot(p[2] - eye[2]) < (aim[1] - eye[1]).max(0.0)
                || !crate::combat::line_of_sight(eye, aim, &arena.solids)
            {
                return Err(invalid(
                    "Notary patrol must be reachable by ordinary guns without overhead aim",
                ));
            }
        }
        Ok(())
    }
}

pub(super) fn validate(
    encounters: &[EncounterDefinition],
    policy: EquipmentPolicy,
    arena: &Arena,
    seen: &mut HashSet<String>,
) -> io::Result<()> {
    if encounters.is_empty() {
        return Ok(());
    }
    if policy != EquipmentPolicy::Discovery
        || encounters.len() > 32
        || encounters.iter().map(|e| e.enemies.len()).sum::<usize>() > 64
        || encounters.iter().map(|e| e.regions.len()).sum::<usize>() > 64
    {
        return Err(invalid(
            "encounters require discovery and bounded groups, enemies and regions",
        ));
    }
    let mut earlier = HashSet::new();
    for encounter in encounters {
        identity(&encounter.id, seen)?;
        if encounter.enemies.is_empty()
            || encounter.regions.is_empty()
            || encounter
                .after
                .as_ref()
                .is_some_and(|id| !earlier.contains(id))
        {
            return Err(invalid(
                "encounter needs enemies, entry regions and only an earlier dependency",
            ));
        }
        for region in &encounter.regions {
            if !region.valid(arena.half) {
                return Err(invalid(
                    "encounter regions need finite ordered bounds within the map",
                ));
            }
        }
        for enemy in &encounter.enemies {
            identity(&enemy.id, seen)?;
            match (&enemy.hover, enemy.kind) {
                (Some(hover), EnemyKind::Notary) => hover
                    .validate(arena, enemy.feet)
                    .map_err(|error| invalid(&format!("enemy {}: {}", enemy.id, error)))?,
                (None, EnemyKind::Notary) => {
                    return Err(invalid("Notary requires hover authoring"))
                }
                (Some(_), _) => return Err(invalid("only Notaries use hover authoring")),
                _ => {}
            }
            if (enemy.seated && enemy.kind != EnemyKind::Clerk)
                || (enemy.hover.is_none() && !standing(arena, enemy.feet))
                || !enemy.yaw.is_finite()
                || !(0.0..std::f32::consts::TAU).contains(&enemy.yaw)
            {
                return Err(invalid(&format!(
                    "enemy {} needs supported feet, full clearance and bounded yaw",
                    enemy.id,
                )));
            }
        }
        earlier.insert(encounter.id.clone());
    }
    Ok(())
}
