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
            if !standing(arena, enemy.feet)
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
