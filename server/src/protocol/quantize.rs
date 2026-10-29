//! Wire quantization of motion (#434 stage 4). Every reader already parses
//! these fields as numbers, so this is no gameplay contract change.
//!
//! The simulation keeps full `f32` values. Only the encoded snapshot rounds
//! them: fighter positions and shot traces to the millimetre, fighter yaw and
//! pitch to a ten-thousandth of a radian. A rounded value prints as at most
//! three or four decimals instead of the up to nine digits of a shortest
//! `f32`, and motion below a step no longer counts as a change in a delta.
//!
//! The rounding uses only IEEE multiply, round and divide, so every host
//! writes the same text for the same value (no libm). The result is the whole
//! number of steps divided by the scale in `f32`, which is the nearest `f32`
//! to that decimal, so its shortest text is that decimal. A value whose step
//! count reaches 2^23 (8,388.608 m for a position; no map comes near it) and
//! a non-finite value pass through unchanged. Step counts up to 2^24 are
//! still whole, but past 2^23 the `f32` spacing near the value is coarser
//! than a step, so rounding a rounded value again could move it; below 2^23
//! rounding is idempotent.

use serde::Serializer;

/// Steps per metre for positions and traces.
pub const POSITION_SCALE: f32 = 1000.0;
/// Steps per radian for yaw and pitch.
pub const ANGLE_SCALE: f32 = 10_000.0;
/// Below 2^23 steps every rounded value rounds to itself again.
const MAX_STEPS: f64 = 8_388_608.0;

fn round(value: f32, scale: f32) -> f32 {
    let steps = (f64::from(value) * f64::from(scale)).round();
    if !steps.is_finite() || steps.abs() >= MAX_STEPS {
        return value;
    }
    // Never write "-0.0" for a value that rounded to zero.
    if steps == 0.0 {
        return 0.0;
    }
    steps as f32 / scale
}

/// A position or distance as the wire carries it.
pub fn position(value: f32) -> f32 {
    round(value, POSITION_SCALE)
}

/// An angle in radians as the wire carries it.
pub fn angle(value: f32) -> f32 {
    round(value, ANGLE_SCALE)
}

/// `serialize_with` for a position field.
pub(crate) fn wire_position<S: Serializer>(value: &f32, serializer: S) -> Result<S::Ok, S::Error> {
    serializer.serialize_f32(position(*value))
}

/// `serialize_with` for an angle field.
pub(crate) fn wire_angle<S: Serializer>(value: &f32, serializer: S) -> Result<S::Ok, S::Error> {
    serializer.serialize_f32(angle(*value))
}

/// `serialize_with` for a point.
pub(crate) fn wire_point<S: Serializer>(
    value: &[f32; 3],
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serde::Serialize::serialize(&value.map(position), serializer)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(value: f32) -> String {
        serde_json::to_string(&value).unwrap()
    }

    #[test]
    fn steps_print_as_short_decimals() {
        // Literal inputs only: no simulated float reaches a golden.
        assert_eq!(text(position(10.123_456)), "10.123");
        assert_eq!(text(position(-3.000_4)), "-3.0");
        assert_eq!(text(position(0.000_4)), "0.0");
        assert_eq!(text(position(-0.000_4)), "0.0");
        assert_eq!(text(position(97.999_6)), "98.0");
        assert_eq!(text(angle(std::f32::consts::FRAC_PI_2)), "1.5708");
        assert_eq!(text(angle(-0.123_449)), "-0.1234");
        assert_eq!(text(angle(std::f32::consts::TAU)), "6.2832");
        for value in [0.1f32, -12.345, 250.75, 1234.567, -9999.999] {
            assert_eq!(position(position(value)), position(value), "{value}");
        }
    }

    #[test]
    fn every_step_in_a_map_prints_at_most_three_decimals() {
        // Sweep whole step counts over a 200 m span: each rounded value's
        // shortest text is its decimal, never a longer neighbour.
        for steps in (-200_000i32..200_000).step_by(7) {
            let value = position(steps as f32 / POSITION_SCALE + 0.000_3);
            let written = text(value);
            let decimals = written.split('.').nth(1).map_or(0, str::len);
            assert!(decimals <= 3, "{steps} wrote {written}");
            let back: f32 = written.parse().unwrap();
            assert_eq!(back, value);
        }
    }

    #[test]
    fn rounding_is_bounded_by_half_a_step() {
        for value in [0.000_49f32, 3.172_59, -47.000_5, 120.009_9, -0.75] {
            assert!((position(value) - value).abs() <= 0.000_5 + 1e-5);
            assert!((angle(value) - value).abs() <= 0.000_05 + 1e-5);
        }
    }

    #[test]
    fn far_and_non_finite_values_pass_through() {
        for value in [
            f32::NAN,
            f32::INFINITY,
            f32::NEG_INFINITY,
            20_000.123,
            -1.0e9,
        ] {
            let out = position(value);
            assert!(out.to_bits() == value.to_bits(), "{value} became {out}");
        }
        assert_eq!(position(16_000.0), 16_000.0);
    }

    #[test]
    fn the_rounding_bound_is_where_it_stays_idempotent() {
        // The last whole steps below 2^23 (8,388,607 is the largest) are
        // rounded, and rounding them again changes nothing.
        for (value, steps) in [(8_388.607f32, 8_388_607.0f32), (-8_388.6, -8_388_600.0)] {
            let near = position(value);
            assert_eq!(near, steps / POSITION_SCALE);
            assert_eq!(position(near).to_bits(), near.to_bits(), "{value}");
            assert_eq!(serde_json::to_string(&near).unwrap(), format!("{value}"));
        }
        // From 2^23 steps on, the value passes through untouched.
        for value in [8_388.608f32, 8_388.609, -8_388.61, 12_000.123] {
            assert_eq!(position(value).to_bits(), value.to_bits(), "{value}");
        }
    }

    #[test]
    fn serializers_round_on_the_wire_only() {
        #[derive(serde::Serialize)]
        struct Row {
            #[serde(serialize_with = "wire_position")]
            x: f32,
            #[serde(serialize_with = "wire_angle")]
            yaw: f32,
            #[serde(serialize_with = "wire_point")]
            at: [f32; 3],
        }
        let row = Row {
            x: 1.234_567,
            yaw: 0.333_333,
            at: [1.000_6, -2.5, 3.333_33],
        };
        assert_eq!(
            serde_json::to_string(&row).unwrap(),
            r#"{"x":1.235,"yaw":0.3333,"at":[1.001,-2.5,3.333]}"#
        );
        assert_eq!(row.x, 1.234_567);
    }
}
