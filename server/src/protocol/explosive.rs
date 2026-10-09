use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AssessorCanisterState {
    pub id: u32,
    pub owner_id: Uuid,
    pub position: [f32; 3],
    pub velocity: [f32; 3],
    pub age_ticks: u32,
}

impl AssessorCanisterState {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.id == 0
            || self.owner_id.is_nil()
            || self.age_ticks >= 80
            || !self
                .position
                .iter()
                .all(|v| v.is_finite() && v.abs() <= 1024.0)
            || !self
                .velocity
                .iter()
                .all(|v| v.is_finite() && v.abs() <= 32.0)
        {
            return Err("invalid Assessor canister state");
        }
        Ok(())
    }
}

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

/// Ticks from sticking to live, two seconds at 20 Hz, with a steady lamp.
pub const MINE_ARMING_TICKS: u64 = 40;
/// Ticks from a trip to the blast, a fast blink a body can still read.
pub const MINE_TRIP_TICKS: u64 = 4;

/// Life of a placed proximity mine. Every transition is a server fact.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MinePhase {
    /// Thrown from the eye, not yet stuck to a surface.
    Flying,
    /// Stuck; the lamp holds steady until `phase_ends`.
    Arming,
    /// Live: a body inside the trigger radius trips it.
    Armed,
    /// Tripped by a body; it detonates at `phase_ends`.
    Tripped,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MineState {
    pub id: u32,
    pub owner_id: Uuid,
    pub position: [f32; 3],
    /// Unit normal of the surface it stuck to. Zero while flying.
    pub normal: [f32; 3],
    pub phase: MinePhase,
    pub phase_started: u64,
    /// Tick the arming or trip window ends; equal to `phase_started` otherwise.
    pub phase_ends: u64,
}

impl MineState {
    pub fn validate(&self, tick: u64) -> Result<(), &'static str> {
        let length = self.normal.iter().map(|v| v * v).sum::<f32>().sqrt();
        let finite = self
            .position
            .iter()
            .chain(&self.normal)
            .all(|v| v.is_finite() && v.abs() <= 1024.0);
        let normal_ok = match self.phase {
            MinePhase::Flying => length == 0.0,
            _ => (length - 1.0).abs() <= 0.001,
        };
        let window_ok = match self.phase {
            MinePhase::Flying | MinePhase::Armed => self.phase_ends == self.phase_started,
            MinePhase::Arming => self.phase_ends == self.phase_started + MINE_ARMING_TICKS,
            MinePhase::Tripped => self.phase_ends == self.phase_started + MINE_TRIP_TICKS,
        };
        if !finite || !normal_ok || !window_ok || self.phase_started > tick {
            return Err("invalid mine state");
        }
        Ok(())
    }
}
