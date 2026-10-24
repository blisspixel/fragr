//! Restoration work facts introduced with Planned Works: marked Paver strips
//! and worn jetpacks. Both are server outcomes; readers only present them.
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// One marked strip, from its near edge `origin` along `yaw` (radians, the
/// same convention as a fighter's facing). `working` is false while the
/// owner prepares and true during the work cycle; the phase window is the
/// owner's own windup or firing window.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaverStripState {
    pub owner_id: Uuid,
    pub origin: [f32; 3],
    pub yaw: f32,
    pub length: f32,
    pub half_width: f32,
    pub working: bool,
    pub phase_started: u64,
    pub phase_ends: u64,
}

/// A worn pack. `fuel` counts live steps of thrust left, at most
/// `movement::jetpack::FUEL_MAX`; `thrusting` is true when the last step burned.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct JetpackState {
    pub player_id: Uuid,
    pub fuel: u16,
    pub thrusting: bool,
}

/// At most one strip per placed Paver; the bound protects readers.
pub const MAX_PAVER_STRIPS: usize = 8;

impl PaverStripState {
    pub fn validate(&self, tick: u64, half_extent: f32) -> Result<(), &'static str> {
        if !self.origin.iter().all(|v| v.is_finite())
            || self.origin[0].abs() > half_extent
            || self.origin[2].abs() > half_extent
            || !(0.0..=512.0).contains(&self.origin[1])
            || !self.yaw.is_finite()
            || !(0.0..std::f32::consts::TAU).contains(&self.yaw)
            || !(crate::encounters::enemy::paver::STRIP_MIN_LENGTH
                ..=crate::encounters::enemy::paver::STRIP_LENGTH)
                .contains(&self.length)
            || self.half_width != crate::encounters::enemy::paver::STRIP_HALF_WIDTH
            || self.phase_started > tick
            || self.phase_ends < self.phase_started
            || self.phase_ends - self.phase_started > 100
        {
            return Err("invalid Paver strip");
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strip_wire_shape_is_strict_and_bounded() {
        let strip = PaverStripState {
            owner_id: Uuid::from_u128(1),
            origin: [1.0, 0.0, 2.0],
            yaw: 0.5,
            length: 10.0,
            half_width: crate::encounters::enemy::paver::STRIP_HALF_WIDTH,
            working: false,
            phase_started: 10,
            phase_ends: 44,
        };
        assert!(strip.validate(20, 40.0).is_ok());
        let text = serde_json::to_string(&strip).unwrap();
        assert_eq!(
            serde_json::from_str::<PaverStripState>(&text).unwrap(),
            strip
        );
        let mut extra: serde_json::Value = serde_json::from_str(&text).unwrap();
        extra["forged"] = serde_json::json!(true);
        assert!(serde_json::from_value::<PaverStripState>(extra).is_err());
        for broken in [
            PaverStripState {
                length: 30.0,
                ..strip
            },
            PaverStripState {
                length: 1.0,
                ..strip
            },
            PaverStripState { yaw: 7.0, ..strip },
            PaverStripState {
                half_width: 4.0,
                ..strip
            },
            PaverStripState {
                origin: [99.0, 0.0, 0.0],
                ..strip
            },
            PaverStripState {
                phase_started: 30,
                ..strip
            },
            PaverStripState {
                phase_ends: 500,
                ..strip
            },
        ] {
            assert!(broken.validate(20, 40.0).is_err(), "{broken:?}");
        }
    }
}
