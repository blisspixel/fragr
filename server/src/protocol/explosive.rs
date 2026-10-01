use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GrenadeState {
    pub id: u32,
    pub owner_id: Uuid,
    pub position: [f32; 3],
    pub fuse_ticks: u32,
    pub bounce_count: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ExplosionHit {
    pub target_id: Uuid,
    pub hp_damage: u32,
    pub armor_damage: u32,
    pub target_hp_after: i32,
    pub killed: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ExplosionResult {
    pub id: u32,
    pub owner_id: Uuid,
    pub position: [f32; 3],
    pub radius: f32,
    pub hits: Vec<ExplosionHit>,
}
