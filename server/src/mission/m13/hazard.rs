//! Bounded machinery cycles. An inactive volume is harmless. The bypass is a
//! separate walk, not a timing window.
use crate::movement::RADIUS;
use crate::protocol::Region3;

pub const TICK_DAMAGE: i32 = 8;
const MAX_PERIOD: u32 = 400;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cycle {
    pub period: u32,
    pub warning: u32,
    pub active: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Idle,
    Warning,
    Active,
}

impl Cycle {
    pub fn validate(self) -> Result<(), &'static str> {
        let safe = self
            .period
            .saturating_sub(self.warning.saturating_add(self.active));
        if self.warning == 0
            || self.active == 0
            || safe == 0
            || self.warning.saturating_add(self.active) >= self.period
            || self.period > MAX_PERIOD
        {
            return Err("foundry cycle has no safe window");
        }
        Ok(())
    }

    pub fn phase(self, tick: u64) -> Phase {
        let place = (tick % u64::from(self.period)) as u32;
        let idle = self.period - self.warning - self.active;
        if place < idle {
            Phase::Idle
        } else if place < idle + self.warning {
            Phase::Warning
        } else {
            Phase::Active
        }
    }
}

pub fn regions_overlap(a: &Region3, b: &Region3) -> bool {
    (0..3).all(|axis| a.min[axis] < b.max[axis] && b.min[axis] < a.max[axis])
}

pub fn body_touches(feet: [f32; 3], height: f32, region: &Region3) -> bool {
    if !height.is_finite() || height <= 0.0 || feet.iter().any(|value| !value.is_finite()) {
        return false;
    }
    let low = feet[1];
    let high = feet[1] + height;
    high > region.min[1]
        && low < region.max[1]
        && feet[0] + RADIUS > region.min[0]
        && feet[0] - RADIUS < region.max[0]
        && feet[2] + RADIUS > region.min[2]
        && feet[2] - RADIUS < region.max[2]
}

pub fn damage(tick: u64, cycle: Cycle, touches: bool) -> i32 {
    if touches && cycle.phase(tick) == Phase::Active {
        TICK_DAMAGE
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cycle() -> Cycle {
        Cycle {
            period: 100,
            warning: 20,
            active: 30,
        }
    }

    fn region() -> Region3 {
        Region3 {
            min: [0.0, 0.0, 0.0],
            max: [2.0, 2.0, 2.0],
        }
    }

    #[test]
    fn cycle_starts_safe_warns_then_hits_only_inside() {
        let cycle = cycle();
        assert_eq!(cycle.phase(0), Phase::Idle);
        assert_eq!(cycle.phase(49), Phase::Idle);
        assert_eq!(cycle.phase(50), Phase::Warning);
        assert_eq!(cycle.phase(69), Phase::Warning);
        assert_eq!(cycle.phase(70), Phase::Active);
        assert_eq!(cycle.phase(99), Phase::Active);
        assert_eq!(cycle.phase(100), Phase::Idle);
        assert_eq!(damage(70, cycle, true), TICK_DAMAGE);
        assert_eq!(damage(70, cycle, false), 0);
        assert_eq!(damage(60, cycle, true), 0);
        assert_eq!(damage(10, cycle, true), 0);
    }

    #[test]
    fn inactive_contact_and_a_separated_bypass_are_safe() {
        let hazard = region();
        assert!(body_touches([1.0, 0.0, 1.0], 1.8, &hazard));
        assert!(!body_touches([4.0, 0.0, 1.0], 1.8, &hazard));
        assert!(!body_touches([1.0, 3.0, 1.0], 1.8, &hazard));
        let bypass = Region3 {
            min: [0.0, 0.0, 2.0],
            max: [2.0, 2.0, 4.0],
        };
        assert!(!regions_overlap(&hazard, &bypass));
        let crossing = Region3 {
            min: [1.0, 0.0, 1.0],
            max: [3.0, 2.0, 3.0],
        };
        assert!(regions_overlap(&hazard, &crossing));
    }

    #[test]
    fn cycle_without_a_warning_or_a_safe_gap_is_rejected() {
        assert!(Cycle {
            period: 40,
            warning: 0,
            active: 20
        }
        .validate()
        .is_err());
        assert!(Cycle {
            period: 40,
            warning: 20,
            active: 20
        }
        .validate()
        .is_err());
        assert!(Cycle {
            period: 500,
            warning: 20,
            active: 20
        }
        .validate()
        .is_err());
        assert!(cycle().validate().is_ok());
    }
}
