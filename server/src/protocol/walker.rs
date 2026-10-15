//! Registered artillery machinery. These are authoritative world facts, not a pawn role.
use super::Region3;
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const WALKER_HP: i32 = 900;
pub const WALKER_SHELLS: u8 = 36;
pub const WALKER_STOMP_RADIUS: f32 = 7.0;
pub const WALKER_SHELL_RADIUS: f32 = 3.0;
pub const WALKER_SPEED: f32 = 1.5;
pub const WALKER_STOMP_WARNING: u64 = 32;
pub const WALKER_ARTILLERY_WARNING: u64 = 40;
pub const WALKER_RECOVERY: u64 = 60;
pub const WALKER_SHELL_LIFE: u32 = 100;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WalkerPhase {
    Dormant,
    StompWarning,
    Stomp,
    ArtilleryWarning,
    Artillery,
    Relocating,
    Recovery,
    Disabled,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalkerGeometry {
    /// Torso first, then four separately shootable joint/leg solids.
    pub solids: [usize; 5],
    /// All registered solids are authored at station zero. Runtime translates
    /// X/Z by accepted feet minus station zero; Y never changes.
    pub stations: [[f32; 3]; 3],
    pub activation: Region3,
    pub arena: Region3,
    pub approach: [f32; 3],
}

pub fn walker_point(p: [f32; 3]) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= 512.0
        && p[2].abs() <= 512.0
        && (0.0..=512.0).contains(&p[1])
}

impl WalkerGeometry {
    pub fn translated(&self, solid: Solid, feet: [f32; 3]) -> Solid {
        let dx = feet[0] - self.stations[0][0];
        let dz = feet[2] - self.stations[0][2];
        Solid {
            min_x: solid.min_x + dx,
            max_x: solid.max_x + dx,
            min_z: solid.min_z + dz,
            max_z: solid.max_z + dz,
            ..solid
        }
    }

    pub fn validate(&self, half: f32, solids: &[Solid]) -> Result<(), &'static str> {
        if !self.activation.valid(half)
            || !self.arena.valid(half)
            || !self.arena.contains(self.activation.min)
            || !self.arena.contains(self.activation.max)
            || self.arena.max[0] - self.arena.min[0] > 120.0
            || self.arena.max[2] - self.arena.min[2] > 120.0
            || !walker_point(self.approach)
            || !self.arena.contains(self.approach)
            || self.stations.iter().enumerate().any(|(i, p)| {
                !walker_point(*p)
                    || p[1] != 0.0
                    || !self.arena.contains(*p)
                    || self.stations[..i].contains(p)
            })
            || self
                .solids
                .iter()
                .enumerate()
                .any(|(i, s)| *s >= solids.len() || self.solids[..i].contains(s))
        {
            return Err("invalid Walker bounds, stations or registered solids");
        }
        let torso = solids[self.solids[0]];
        if torso.bottom < 3.0
            || torso.top > 12.0
            || torso.top - torso.bottom < 1.0
            || !torso.covers(self.stations[0][0], self.stations[0][2])
        {
            return Err("Walker torso must be raised with a readable body");
        }
        for (i, index) in self.solids.iter().enumerate() {
            let s = solids[*index];
            if i > 0 && (s.bottom != 0.0 || s.top < 2.0 || s.top > torso.bottom) {
                return Err("Walker joints require grounded legs below its torso");
            }
            for station in self.stations {
                let s = self.translated(s, station);
                if !self.arena.contains([s.min_x, s.bottom, s.min_z])
                    || !self.arena.contains([s.max_x, s.top, s.max_z])
                {
                    return Err("Walker body leaves its authored arena");
                }
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalkerShellState {
    pub id: u32,
    pub position: [f32; 3],
    pub velocity: [f32; 3],
    pub age_ticks: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WalkerState {
    pub hp: i32,
    pub stage: u8,
    pub phase: WalkerPhase,
    pub phase_started: u64,
    pub phase_ends: u64,
    pub feet: [f32; 3],
    pub target: [f32; 3],
    pub artillery_targets: [[f32; 3]; 3],
    pub shells_left: u8,
    pub shells: Vec<WalkerShellState>,
}

impl WalkerState {
    pub fn validate(&self, tick: u64) -> Result<(), &'static str> {
        let duration = match self.phase {
            WalkerPhase::Dormant | WalkerPhase::Disabled => 0,
            WalkerPhase::StompWarning => WALKER_STOMP_WARNING,
            WalkerPhase::Stomp => 4,
            WalkerPhase::ArtilleryWarning => WALKER_ARTILLERY_WARNING,
            WalkerPhase::Artillery => 16,
            WalkerPhase::Relocating => 400,
            WalkerPhase::Recovery => WALKER_RECOVERY,
        };
        if !(0..=WALKER_HP).contains(&self.hp)
            || self.stage
                != if self.hp > 600 {
                    1
                } else if self.hp > 300 {
                    2
                } else {
                    3
                }
            || self.shells_left > WALKER_SHELLS
            || self.phase_started > tick
            || self.phase_ends < self.phase_started
            || self.phase_ends - self.phase_started != duration
            || duration > 0 && self.phase_ends <= tick
            || !walker_point(self.feet)
            || self.feet[1] != 0.0
            || !walker_point(self.target)
            || self.artillery_targets.iter().any(|p| !walker_point(*p))
            || (self.hp == 0) != (self.phase == WalkerPhase::Disabled)
            || self.phase == WalkerPhase::Dormant
                && (self.hp != WALKER_HP
                    || self.phase_started != 0
                    || self.shells_left != WALKER_SHELLS
                    || !self.shells.is_empty())
            || self.shells.len() > 6
            || self.shells.len() + usize::from(self.shells_left) > usize::from(WALKER_SHELLS)
            || self.shells.iter().enumerate().any(|(i, shell)| {
                shell.id == 0
                    || self.shells[..i].iter().any(|s| s.id == shell.id)
                    || !walker_point(shell.position)
                    || shell
                        .velocity
                        .iter()
                        .any(|v| !v.is_finite() || v.abs() > 128.0)
                    || shell.age_ticks >= WALKER_SHELL_LIFE
            })
        {
            Err("invalid Walker snapshot")
        } else {
            Ok(())
        }
    }
}
