use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const MAX_MAP_DECORATIONS: usize = 128;
pub const MAX_MAP_LIGHTS: usize = 8;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MapFace {
    West,
    East,
    Down,
    Up,
    North,
    South,
}

impl MapFace {
    pub fn dimensions(self, solid: &Solid) -> [f32; 2] {
        let x = solid.max_x - solid.min_x;
        let y = solid.top - solid.bottom;
        let z = solid.max_z - solid.min_z;
        match self {
            Self::West | Self::East => [z, y],
            Self::Down | Self::Up => [x, z],
            Self::North | Self::South => [x, y],
        }
    }
}

/// Registered offline art and text keys. A map cannot supply resource paths.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MapDecorationKind {
    PropertySign,
    IntakeSign,
    RecordsSign,
    MaintenanceSign,
    TransferSign,
    LiftSign,
    ComplaintNotice,
    UnionSeal,
    Lockers,
    Vent,
    Terminal,
    StripLight,
    LiftControl,
    /// M02 gate signal: red lamp over a closed shutter pictogram. Authored only
    /// through a gate, which flips it to `GateOpen` in every world where it is raised.
    GateLocked,
    /// Green lamp over a raised shutter and up arrow, on the gate and its opener.
    GateOpen,
}

/// Authoring names a solid; the validated wire form uses its index. The same
/// fields and enum parser apply at both boundaries, without flattening JSON.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct MapDecoration<S = usize> {
    pub solid: S,
    pub face: MapFace,
    /// Metres along the face's right/up axes, relative to its centre.
    pub center: [f32; 2],
    pub size: [f32; 2],
    pub kind: MapDecorationKind,
}

impl<S> MapDecoration<S> {
    /// Point just outside the host face, matching MapDecoration.placement in Godot.
    pub fn point(&self, host: &Solid) -> [f32; 3] {
        let [u, v] = self.center;
        let center = [
            (host.min_x + host.max_x) * 0.5,
            (host.bottom + host.top) * 0.5,
            (host.min_z + host.max_z) * 0.5,
        ];
        const OFFSET: f32 = 0.012;
        match self.face {
            MapFace::West => [host.min_x - OFFSET, center[1] + v, center[2] + u],
            MapFace::East => [host.max_x + OFFSET, center[1] + v, center[2] - u],
            MapFace::Down => [center[0] + u, host.bottom - OFFSET, center[2] + v],
            MapFace::Up => [center[0] + u, host.top + OFFSET, center[2] - v],
            MapFace::North => [center[0] - u, center[1] + v, host.min_z - OFFSET],
            MapFace::South => [center[0] + u, center[1] + v, host.max_z + OFFSET],
        }
    }

    pub fn with_solid<T>(self, solid: T) -> MapDecoration<T> {
        MapDecoration {
            solid,
            face: self.face,
            center: self.center,
            size: self.size,
            kind: self.kind,
        }
    }
}

pub fn validate_decorations(
    decorations: &[MapDecoration],
    solids: &[Solid],
) -> Result<(), &'static str> {
    if decorations.len() > MAX_MAP_DECORATIONS
        || decorations
            .iter()
            .filter(|d| d.kind == MapDecorationKind::StripLight)
            .count()
            > MAX_MAP_LIGHTS
    {
        return Err("map decoration or light budget exceeded");
    }
    for detail in decorations {
        let Some(host) = solids.get(detail.solid) else {
            return Err("map decoration references an unknown solid");
        };
        let dimensions = detail.face.dimensions(host);
        for (axis, extent) in dimensions.into_iter().enumerate() {
            let center = detail.center[axis];
            let size = detail.size[axis];
            if !extent.is_finite()
                || extent <= 0.0
                || !center.is_finite()
                || !size.is_finite()
                || !(0.125..=16.0).contains(&size)
                || center.abs() + size * 0.5 > extent * 0.5
            {
                return Err("map decoration exceeds its solid face");
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests;
