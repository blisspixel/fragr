//! Registered water volumes shared by movement, vehicles and presentation.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterRegion {
    pub min: [f32; 2],
    pub max: [f32; 2],
    pub level: f32,
    pub depth: f32,
}

impl WaterRegion {
    pub fn contains(&self, x: f32, z: f32) -> bool {
        x >= self.min[0] && x <= self.max[0] && z >= self.min[1] && z <= self.max[1]
    }
}

pub fn validate_water_regions(regions: &[WaterRegion], half: f32) -> Result<(), &'static str> {
    if regions.len() > 32 || !half.is_finite() || half <= 0.0 {
        return Err("invalid water bounds");
    }
    for (index, region) in regions.iter().enumerate() {
        if !region.level.is_finite()
            || !region.depth.is_finite()
            || region.depth <= 0.0
            || region.depth > 64.0
            || region.level < region.depth
            || region.level > half * 2.0
            || !region
                .min
                .into_iter()
                .chain(region.max)
                .all(|v| v.is_finite() && v.abs() <= half)
            || region.min[0] >= region.max[0]
            || region.min[1] >= region.max[1]
        {
            return Err("invalid water region");
        }
        if regions[..index].iter().any(|other| {
            region.min[0] < other.max[0]
                && region.max[0] > other.min[0]
                && region.min[1] < other.max[1]
                && region.max[1] > other.min[1]
        }) {
            return Err("overlapping water regions");
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn water() -> WaterRegion {
        WaterRegion {
            min: [-10.0, -10.0],
            max: [0.0, 10.0],
            level: 2.2,
            depth: 2.2,
        }
    }

    #[test]
    fn water_regions_allow_shared_edges_but_reject_overlap_and_excess_count() {
        let left = water();
        let right = WaterRegion {
            min: [0.0, -10.0],
            max: [10.0, 10.0],
            ..left
        };
        assert!(validate_water_regions(&[left, right], 10.0).is_ok());
        let overlap = WaterRegion {
            min: [-0.01, -10.0],
            ..right
        };
        assert_eq!(
            validate_water_regions(&[left, overlap], 10.0),
            Err("overlapping water regions")
        );
        assert!(validate_water_regions(&[left; 33], 10.0).is_err());
    }

    #[test]
    fn water_regions_refuse_nonfinite_inverted_and_impossible_depths() {
        for region in [
            WaterRegion {
                level: f32::NAN,
                ..water()
            },
            WaterRegion {
                depth: f32::INFINITY,
                ..water()
            },
            WaterRegion {
                min: [f32::NEG_INFINITY, -10.0],
                ..water()
            },
            WaterRegion {
                max: [f32::NAN, 10.0],
                ..water()
            },
            WaterRegion {
                depth: 0.0,
                ..water()
            },
            WaterRegion {
                depth: -1.0,
                ..water()
            },
            WaterRegion {
                depth: 2.3,
                ..water()
            },
            WaterRegion {
                depth: 65.0,
                level: 65.0,
                ..water()
            },
            WaterRegion {
                level: 21.0,
                ..water()
            },
            WaterRegion {
                min: [0.0, -10.0],
                ..water()
            },
            WaterRegion {
                min: [1.0, -10.0],
                ..water()
            },
            WaterRegion {
                min: [-10.01, -10.0],
                ..water()
            },
        ] {
            assert!(
                validate_water_regions(&[region], 10.0).is_err(),
                "{region:?}"
            );
        }
        for half in [0.0, -1.0, f32::NAN, f32::INFINITY] {
            assert!(validate_water_regions(&[], half).is_err());
        }
        let mut value = serde_json::to_value(water()).unwrap();
        value["current"] = serde_json::json!([1, 0]);
        assert!(serde_json::from_value::<WaterRegion>(value).is_err());
    }
}
