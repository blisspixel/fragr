//! Authoritative aim and finite shot intersections in world coordinates.

use crate::movement::Solid;

pub const PITCH_LIMIT: f32 = 85.0 * std::f32::consts::PI / 180.0;
pub const FIGHTER_HEIGHT: f32 = crate::movement::BODY_HEIGHT;

pub fn clamp_pitch(pitch: f32) -> Option<f32> {
    pitch
        .is_finite()
        .then(|| pitch.clamp(-PITCH_LIMIT, PITCH_LIMIT))
}

/// Positive pitch looks upward. Yaw zero points along world +X.
pub fn aim_at(origin: [f32; 3], target: [f32; 3]) -> Option<(f32, f32)> {
    if origin.iter().chain(target.iter()).any(|v| !v.is_finite()) {
        return None;
    }
    let [dx, dy, dz] = std::array::from_fn(|i| f64::from(target[i]) - f64::from(origin[i]));
    let horizontal = dx.hypot(dz);
    if horizontal == 0.0 && dy == 0.0 {
        return None;
    }
    Some((
        (dz.atan2(dx) as f32).rem_euclid(std::f32::consts::TAU),
        (dy.atan2(horizontal) as f32).clamp(-PITCH_LIMIT, PITCH_LIMIT),
    ))
}

/// Visibility between world points, using the same solid volumes as shots.
/// This is an agent observation helper, not permission to deal damage.
pub fn line_of_sight(origin: [f32; 3], target: [f32; 3], solids: &[Solid]) -> bool {
    if origin.iter().chain(target.iter()).any(|v| !v.is_finite()) {
        return false;
    }
    let delta: [f64; 3] = std::array::from_fn(|i| f64::from(target[i]) - f64::from(origin[i]));
    let length = delta.iter().map(|v| v * v).sum::<f64>().sqrt();
    if length == 0.0 {
        return true;
    }
    let distance = length as f32;
    if !distance.is_finite() {
        return false;
    }
    let ray = Ray {
        origin,
        direction: delta.map(|v| (v / length) as f32),
    };
    !ray.floor(distance).is_some_and(|t| t < distance)
        && !solids.iter().any(|solid| {
            ray.solid(solid, distance)
                .is_some_and(|hit| hit.distance < distance)
        })
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct Ray {
    pub(crate) origin: [f32; 3],
    pub(crate) direction: [f32; 3],
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct SurfaceHit {
    pub distance: f32,
    pub normal: [f32; 3],
}

impl Ray {
    pub fn point(self, distance: f32) -> [f32; 3] {
        std::array::from_fn(|i| self.origin[i] + self.direction[i] * distance)
    }

    /// Uniform disk in the plane perpendicular to aim, projected into the cone.
    /// Callers supply the two seeded samples, keeping RNG ownership in the sim.
    pub fn dispersed(
        origin: [f32; 3],
        yaw: f32,
        pitch: f32,
        spread: f32,
        samples: [f32; 2],
    ) -> Self {
        let (sy, cy) = yaw.sin_cos();
        let (sp, cp) = pitch.sin_cos();
        let forward = [cp * cy, sp, cp * sy];
        let right = [-sy, 0.0, cy];
        let up = [-sp * cy, cp, -sp * sy];
        let radius = samples[0].sqrt() * spread.tan();
        let (s, c) = (samples[1] * std::f32::consts::TAU).sin_cos();
        let mut direction: [f32; 3] =
            std::array::from_fn(|i| forward[i] + radius * (c * right[i] + s * up[i]));
        let length = direction.iter().map(|v| v * v).sum::<f32>().sqrt();
        direction.iter_mut().for_each(|v| *v /= length);
        Self { origin, direction }
    }

    /// First intersection with a closed vertical cylinder, measured along the ray.
    pub fn fighter(self, feet: [f32; 3], radius: f32, range: f32) -> Option<SurfaceHit> {
        let ox = f64::from(self.origin[0]) - f64::from(feet[0]);
        let oz = f64::from(self.origin[2]) - f64::from(feet[2]);
        let dx = f64::from(self.direction[0]);
        let dz = f64::from(self.direction[2]);
        let a = dx * dx + dz * dz;
        let b = ox * dx + oz * dz;
        let c = ox * ox + oz * oz - f64::from(radius).powi(2);
        let mut near = 0.0_f64;
        let mut far = f64::from(range);
        if a == 0.0 {
            if c > 0.0 {
                return None;
            }
        } else {
            let discriminant = b * b - a * c;
            if discriminant < 0.0 {
                return None;
            }
            let root = discriminant.sqrt();
            near = near.max((-b - root) / a);
            far = far.min((-b + root) / a);
        }
        let side_near = near;
        clip_slab(
            self.origin[1],
            self.direction[1],
            feet[1],
            feet[1] + FIGHTER_HEIGHT,
            &mut near,
            &mut far,
        )?;
        if near > far {
            return None;
        }
        let distance = near as f32;
        let normal = if distance == 0.0 {
            self.direction.map(|v| -v)
        } else if near > side_near {
            [0.0, -self.direction[1].signum(), 0.0]
        } else {
            let point = self.point(distance);
            let x = point[0] - feet[0];
            let z = point[2] - feet[2];
            let length = x.hypot(z);
            [x / length, 0.0, z / length]
        };
        Some(SurfaceHit { distance, normal })
    }

    /// Intersect the exact volume, including the underside of a raised slab.
    pub fn solid(self, solid: &Solid, range: f32) -> Option<SurfaceHit> {
        let low = [solid.min_x, solid.bottom, solid.min_z];
        let high = [solid.max_x, solid.top, solid.max_z];
        let mut near = 0.0_f64;
        let mut far = f64::from(range);
        let mut normal = self.direction.map(|v| -v);
        for axis in 0..3 {
            let previous_near = near;
            clip_slab(
                self.origin[axis],
                self.direction[axis],
                low[axis],
                high[axis],
                &mut near,
                &mut far,
            )?;
            if near > previous_near {
                normal = [0.0; 3];
                normal[axis] = -self.direction[axis].signum();
            }
        }
        Some(SurfaceHit {
            distance: near as f32,
            normal,
        })
    }

    pub fn floor(self, range: f32) -> Option<f32> {
        if self.direction[1] >= 0.0 {
            return None;
        }
        let distance = -self.origin[1] / self.direction[1];
        (distance >= 0.0 && distance <= range).then_some(distance)
    }
}

fn clip_slab(
    origin: f32,
    direction: f32,
    low: f32,
    high: f32,
    near: &mut f64,
    far: &mut f64,
) -> Option<()> {
    if direction == 0.0 {
        return (origin >= low && origin <= high).then_some(());
    }
    let first = (f64::from(low) - f64::from(origin)) / f64::from(direction);
    let second = (f64::from(high) - f64::from(origin)) / f64::from(direction);
    *near = near.max(first.min(second));
    *far = far.min(first.max(second));
    (*near <= *far).then_some(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ray(origin: [f32; 3], direction: [f32; 3]) -> Ray {
        Ray { origin, direction }
    }

    #[test]
    fn finite_cylinder_has_sides_caps_and_no_infinite_vertical_hits() {
        let feet = [10.0, 0.0, 0.0];
        assert_eq!(
            ray([0.0, 1.6, 0.0], [1.0, 0.0, 0.0]).fighter(feet, 0.5, 10.0),
            Some(SurfaceHit {
                distance: 9.5,
                normal: [-1.0, 0.0, 0.0]
            })
        );
        assert_eq!(
            ray([0.0, 2.0, 0.0], [1.0, 0.0, 0.0]).fighter(feet, 0.5, 20.0),
            None
        );
        assert_eq!(
            ray([10.0, 3.8, 0.0], [0.0, -1.0, 0.0]).fighter(feet, 0.5, 20.0),
            Some(SurfaceHit {
                distance: 2.0,
                normal: [0.0, 1.0, 0.0]
            })
        );
        assert_eq!(
            ray([11.0, 3.0, 0.0], [0.0, -1.0, 0.0]).fighter(feet, 0.5, 20.0),
            None
        );
        assert_eq!(
            ray([10.0, 1.0, 0.0], [1.0, 0.0, 0.0]).fighter(feet, 0.5, 20.0),
            Some(SurfaceHit {
                distance: 0.0,
                normal: [-1.0, 0.0, 0.0]
            })
        );
        assert_eq!(
            ray([12.0, 1.0, 0.0], [1.0, 0.0, 0.0]).fighter(feet, 0.5, 20.0),
            None
        );
        assert_eq!(
            ray([0.0, 1.0, 0.0], [1.0, 0.0, 0.0]).fighter(feet, 0.5, 9.4),
            None
        );
        assert_eq!(
            ray([0.0, 1.0, 0.0], [1.0, 0.0, 0.0]).fighter(feet, 0.5, 9.5),
            Some(SurfaceHit {
                distance: 9.5,
                normal: [-1.0, 0.0, 0.0]
            }),
            "the range endpoint belongs to the shot"
        );
        assert_eq!(
            ray([0.0, 1.0, 1.0], [1.0, 0.0, 0.0]).fighter(feet, 0.5, 20.0),
            None
        );
    }

    #[test]
    fn descending_ray_hits_solid_top_after_entering_above_its_side() {
        let solid = Solid {
            min_x: 1.0,
            max_x: 5.0,
            min_z: -1.0,
            max_z: 1.0,
            bottom: 0.0,
            top: 2.0,
        };
        let diagonal = std::f32::consts::FRAC_1_SQRT_2;
        let shot = ray([0.0, 4.0, 0.0], [diagonal, -diagonal, 0.0]);
        let hit = shot.solid(&solid, 20.0).unwrap();
        assert!((hit.distance - 2.0 / diagonal).abs() < 1e-5);
        assert_eq!(hit.normal, [0.0, 1.0, 0.0]);
        assert!(ray([0.0, 3.0, 0.0], [1.0, 0.0, 0.0])
            .solid(&solid, 20.0)
            .is_none());
        assert!(ray([0.0, 1.0, 2.0], [1.0, 0.0, 0.0])
            .solid(&solid, 20.0)
            .is_none());
        assert!(ray([0.0, 1.0, 0.0], [-1.0, 0.0, 0.0])
            .solid(&solid, 20.0)
            .is_none());
        assert_eq!(
            ray([1.0, 1.0, 0.0], [0.0, 1.0, 0.0]).solid(&solid, 20.0),
            Some(SurfaceHit {
                distance: 0.0,
                normal: [0.0, -1.0, 0.0]
            })
        );
        assert!(shot.solid(&solid, 1.0).is_none());
        assert_eq!(
            ray([0.0, 1.0, 0.0], [1.0, 1e-10, 1e-10]).solid(&solid, 20.0),
            Some(SurfaceHit {
                distance: 1.0,
                normal: [-1.0, 0.0, 0.0]
            }),
            "near-parallel components must not invalidate a side intersection"
        );
        assert!(ray([0.0, 3.0, 0.0], [1.0, -1e-10, 0.0])
            .solid(&solid, 20.0)
            .is_none());
    }

    #[test]
    fn aim_and_dispersion_are_finite_unit_directions_inside_the_cone() {
        assert_eq!(aim_at([0.0; 3], [0.0; 3]), None);
        assert_eq!(aim_at([0.0; 3], [f32::INFINITY, 1.0, 0.0]), None);
        assert_eq!(clamp_pitch(f32::NAN), None);
        assert_eq!(clamp_pitch(10.0), Some(PITCH_LIMIT));
        assert_eq!(clamp_pitch(-10.0), Some(-PITCH_LIMIT));
        assert!(aim_at([-f32::MAX; 3], [f32::MAX; 3]).unwrap().1.is_finite());
        let (yaw, pitch) = aim_at([0.0; 3], [1.0, 1.0, 0.0]).unwrap();
        assert_eq!(yaw, 0.0);
        assert!((pitch - std::f32::consts::FRAC_PI_4).abs() < 1e-6);
        let centre = Ray::dispersed([0.0; 3], yaw, pitch, 0.0, [0.5, 0.2]);
        for radial in [0.0, 0.1, 0.5, 0.999] {
            for angle in [0.0, 0.25, 0.5, 0.75] {
                let shot = Ray::dispersed([0.0; 3], yaw, pitch, 0.2, [radial, angle]);
                let length = shot.direction.iter().map(|v| v * v).sum::<f32>();
                assert!((length - 1.0).abs() < 1e-6);
                let dot = shot
                    .direction
                    .iter()
                    .zip(centre.direction)
                    .map(|(a, b)| a * b)
                    .sum::<f32>();
                assert!(dot >= 0.2_f32.cos() - 1e-6);
            }
        }
        assert_eq!(ray([0.0, 2.0, 0.0], [0.0, -1.0, 0.0]).floor(3.0), Some(2.0));
        assert_eq!(ray([0.0, 2.0, 0.0], [0.0, -1.0, 0.0]).floor(1.0), None);
        assert_eq!(ray([0.0, 2.0, 0.0], [0.0, 1.0, 0.0]).floor(3.0), None);
    }

    #[test]
    fn visibility_uses_height_and_rejects_invalid_points() {
        let solids = [Solid {
            min_x: 1.0,
            max_x: 5.0,
            min_z: -1.0,
            max_z: 1.0,
            bottom: 0.0,
            top: 2.0,
        }];
        assert!(!line_of_sight([0.0, 1.0, 0.0], [10.0, 1.0, 0.0], &solids));
        assert!(line_of_sight([0.0, 3.0, 0.0], [10.0, 3.0, 0.0], &solids));
        assert!(!line_of_sight([0.0, 4.0, 0.0], [6.0, 0.0, 0.0], &solids));
        assert!(!line_of_sight([0.0, 1.0, 0.0], [0.0, -1.0, 0.0], &[]));
        assert!(!line_of_sight([f32::NAN; 3], [0.0; 3], &[]));
        assert!(!line_of_sight([-f32::MAX; 3], [f32::MAX; 3], &[]));
        assert!(line_of_sight([0.0; 3], [0.0; 3], &[]));
    }
}
