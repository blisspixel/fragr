use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const VEHICLE_GAMEPLAY_VERSION: u32 = 39;
pub const MAX_VEHICLES: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VehicleSeat {
    Driver,
    Gunner,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VehicleKind {
    Jeep,
    Boat,
    LightAircraft,
}

/// Seats are the sole occupancy fact. Ground-base position uses metres and
/// the same +X-forward yaw as ordinary actors.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VehicleState {
    pub id: u32,
    pub kind: VehicleKind,
    pub position: [f32; 3],
    pub yaw: f32,
    pub speed: f32,
    pub vy: f32,
    pub hp: i32,
    pub driver: Option<Uuid>,
    pub gunner: Option<Uuid>,
    pub gun_heat: f32,
    pub burning_ticks: u32,
    pub control_ready_tick: u64,
}

impl VehicleState {
    pub fn seat(&self, id: Uuid) -> Option<VehicleSeat> {
        if self.driver == Some(id) {
            Some(VehicleSeat::Driver)
        } else if self.gunner == Some(id) {
            Some(VehicleSeat::Gunner)
        } else {
            None
        }
    }

    pub fn validate(&self) -> bool {
        self.id > 0
            && self
                .position
                .iter()
                .all(|v| v.is_finite() && v.abs() <= 1_000_000.0)
            && self.yaw.is_finite()
            && (0.0..std::f32::consts::TAU).contains(&self.yaw)
            && self.speed.is_finite()
            && self.speed.abs()
                <= if self.kind == VehicleKind::LightAircraft {
                    32.0
                } else {
                    20.0
                }
            && self.vy.is_finite()
            && (0..=400).contains(&self.hp)
            && self.gun_heat.is_finite()
            && (0.0..=1.0).contains(&self.gun_heat)
            && self.burning_ticks <= 40
            && (self.hp == 0 || self.burning_ticks == 0)
            && (self.driver.is_none() || self.driver != self.gunner)
            && (self.kind != VehicleKind::LightAircraft || self.gunner.is_none())
    }
}
