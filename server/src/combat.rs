//! Authoritative aim and finite shot intersections in world coordinates.

use crate::movement::Solid;
use crate::protocol::{CampaignActor, EnemyKind};

pub const PITCH_LIMIT: f32 = 85.0 * std::f32::consts::PI / 180.0;
pub const FIGHTER_HEIGHT: f32 = crate::movement::BODY_HEIGHT;
/// The Crawler's physical clearance and finite shot volume.
pub const CRAWLER_HEIGHT: f32 = 0.8;
pub const NOTARY_HEIGHT: f32 = 0.7;
pub const NOTARY_HALF_WIDTH: f32 = 0.65;
pub fn is_notary(identity: Option<CampaignActor>) -> bool {
    matches!(
        identity,
        Some(CampaignActor::Union {
            kind: EnemyKind::Notary,
            ..
        })
    )
}

/// An Auditor holding a repair channel on a disabled body.
pub fn channeling(identity: Option<CampaignActor>) -> bool {
    matches!(
        identity,
        Some(CampaignActor::Union {
            kind: EnemyKind::Auditor,
            phase: crate::protocol::EnemyPhase::Channeling,
            ..
        })
    )
}

/// Engagement order shared by every controller: a channeling Auditor comes
/// before any nearer hostile, so agents break a repair before it lands.
/// Otherwise nearer is first. Compare keys with `engagement_before`.
pub fn engagement_key(identity: Option<CampaignActor>, distance: f32) -> (bool, f32) {
    (!channeling(identity), distance)
}

pub fn engagement_before(a: (bool, f32), b: (bool, f32)) -> bool {
    (!a.0 && b.0) || (a.0 == b.0 && a.1 < b.1)
}

pub fn target_height(identity: Option<CampaignActor>) -> f32 {
    if is_notary(identity) {
        return NOTARY_HEIGHT;
    }
    if matches!(
        identity,
        Some(CampaignActor::Union {
            kind: EnemyKind::Crawler,
            ..
        })
    ) {
        CRAWLER_HEIGHT
    } else {
        FIGHTER_HEIGHT
    }
}

pub fn eye_height(identity: Option<CampaignActor>) -> f32 {
    if is_notary(identity) {
        return NOTARY_HEIGHT * 0.5;
    }
    if matches!(
        identity,
        Some(CampaignActor::Union {
            kind: EnemyKind::Crawler,
            ..
        })
    ) {
        0.55
    } else {
        crate::movement::EYE_HEIGHT
    }
}

/// Collision height for this stance. Short bodies never crouch.
pub fn body_height(identity: Option<CampaignActor>, ducking: bool) -> f32 {
    if ducking && !short_body(identity) {
        crate::movement::DUCK_HEIGHT
    } else {
        target_height(identity)
    }
}

/// Shot and view height for this stance. The short eye keeps the standing
/// gap under the crown.
pub fn stance_eye(identity: Option<CampaignActor>, ducking: bool) -> f32 {
    if ducking && !short_body(identity) {
        crate::movement::DUCK_EYE_HEIGHT
    } else {
        eye_height(identity)
    }
}

/// Breastplate height on the character rig. Half of [`FIGHTER_HEIGHT`] is the hips.
pub const TORSO_HEIGHT: f32 = 1.22;
/// Where a standing fighter's head begins, metres above the feet. Just above
/// the breastplate, so a chest aim stays a body shot and an eye-level ray does not.
pub const HEAD_GATE: f32 = 1.45;
/// Traced pellets in the head band. Fists and the Shiv never use it.
pub const HEAD_DAMAGE_SCALE: i32 = 2;

/// A pellet struck the head. Short bodies use the top quarter, so a shot
/// through the middle of a Crawler or a Notary stays a body shot.
pub fn head_hit(feet_y: f32, impact_y: f32, identity: Option<CampaignActor>) -> bool {
    if !feet_y.is_finite() || !impact_y.is_finite() {
        return false;
    }
    let height = target_height(identity);
    let top = feet_y + height + 0.05;
    let gate = if short_body(identity) {
        feet_y + height * 0.75
    } else {
        feet_y + HEAD_GATE
    };
    impact_y >= gate && impact_y <= top
}

/// Head band after a crouch. The standing gate and the crown both drop by the
/// difference between the two body heights. A level shot at the standing eye
/// passes over the short body. A standing-chest aim lands in the short head.
pub fn head_hit_for(
    feet_y: f32,
    impact_y: f32,
    identity: Option<CampaignActor>,
    ducking: bool,
) -> bool {
    if !ducking || short_body(identity) {
        return head_hit(feet_y, impact_y, identity);
    }
    if !feet_y.is_finite() || !impact_y.is_finite() {
        return false;
    }
    let drop = crate::movement::BODY_HEIGHT - crate::movement::DUCK_HEIGHT;
    let top = feet_y + crate::movement::DUCK_HEIGHT + 0.05;
    let gate = feet_y + HEAD_GATE - drop;
    impact_y >= gate && impact_y <= top
}

/// Body damage, or double when the pellet is in the head band. Fists and the
/// Shiv stay flat: a punch to the face is still a punch.
pub fn traced_damage(weapon: crate::protocol::WeaponType, body: i32, head: bool) -> i32 {
    if head
        && !matches!(
            weapon,
            crate::protocol::WeaponType::Fists | crate::protocol::WeaponType::Shiv
        )
    {
        body.saturating_mul(HEAD_DAMAGE_SCALE)
    } else {
        body
    }
}

/// Where a gun is aimed, in metres above the feet.
///
/// A standing fighter's capsule centre is the belt. Shots lock on the chest.
/// A Crawler and a Notary are short volumes, so the middle of that volume is the body.
pub fn aim_height(identity: Option<CampaignActor>) -> f32 {
    if is_notary(identity)
        || matches!(
            identity,
            Some(CampaignActor::Union {
                kind: EnemyKind::Crawler,
                ..
            })
        )
    {
        target_height(identity) * 0.5
    } else {
        TORSO_HEIGHT
    }
}

/// `feet` is the world position of the feet.
pub fn aim_point(feet: [f32; 3], identity: Option<CampaignActor>) -> [f32; 3] {
    [feet[0], feet[1] + aim_height(identity), feet[2]]
}

/// Chest aim for the resolved stance. A crouch drops the point with the body.
pub fn aim_point_for(feet: [f32; 3], identity: Option<CampaignActor>, ducking: bool) -> [f32; 3] {
    let mut point = aim_point(feet, identity);
    if ducking && !short_body(identity) {
        point[1] -= crate::movement::BODY_HEIGHT - crate::movement::DUCK_HEIGHT;
    }
    point
}

fn short_body(identity: Option<CampaignActor>) -> bool {
    is_notary(identity)
        || matches!(
            identity,
            Some(CampaignActor::Union {
                kind: EnemyKind::Crawler,
                ..
            })
        )
}

/// Chest when the fighter is clearly in the open. Any cover, including a lip
/// the bottom of the scatter cone would still strike, keeps the hip line. A
/// short body has one point.
pub fn shot_aim(
    feet: [f32; 3],
    identity: Option<CampaignActor>,
    eye: [f32; 3],
    solids: &[crate::movement::Solid],
) -> [f32; 3] {
    let chest = aim_point(feet, identity);
    if short_body(identity) {
        return chest;
    }
    let hips = [feet[0], feet[1] + target_height(identity) * 0.5, feet[2]];
    let hips_open = line_of_sight(eye, hips, solids);
    let chest_open = line_of_sight(eye, chest, solids);
    if hips_open && chest_open && belt_has_daylight(eye, hips, solids) {
        chest
    } else {
        hips
    }
}

/// Cover choice for a crouched fighter. The feet are lowered by the crouch
/// drop so the standing chest and hip lines land on the short body.
pub fn shot_aim_for(
    feet: [f32; 3],
    identity: Option<CampaignActor>,
    ducking: bool,
    eye: [f32; 3],
    solids: &[crate::movement::Solid],
) -> [f32; 3] {
    if !ducking || short_body(identity) {
        return shot_aim(feet, identity, eye, solids);
    }
    let mut lowered = feet;
    lowered[1] -= crate::movement::BODY_HEIGHT - crate::movement::DUCK_HEIGHT;
    shot_aim(lowered, identity, eye, solids)
}

/// The belt is not "open" when the bottom of a scatter cone under that line
/// still hits cover or the floor. Lifting the aim there skips the lip.
fn belt_has_daylight(eye: [f32; 3], hips: [f32; 3], solids: &[Solid]) -> bool {
    let horizontal = (hips[0] - eye[0]).hypot(hips[2] - eye[2]);
    let drop = horizontal * crate::protocol::WeaponType::Scatter.spread_radians().tan();
    drop.is_finite() && line_of_sight(eye, [hips[0], (hips[1] - drop).max(0.05), hips[2]], solids)
}

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
    /// Airborne equipment uses its actual raised box, never a ground capsule.
    pub fn actor(
        self,
        feet: [f32; 3],
        identity: Option<CampaignActor>,
        range: f32,
    ) -> Option<SurfaceHit> {
        if is_notary(identity) {
            self.solid(
                &Solid {
                    min_x: feet[0] - NOTARY_HALF_WIDTH,
                    max_x: feet[0] + NOTARY_HALF_WIDTH,
                    min_z: feet[2] - NOTARY_HALF_WIDTH,
                    max_z: feet[2] + NOTARY_HALF_WIDTH,
                    bottom: feet[1],
                    top: feet[1] + NOTARY_HEIGHT,
                },
                range,
            )
        } else {
            self.fighter_with_height(
                feet,
                crate::movement::RADIUS,
                target_height(identity),
                range,
            )
        }
    }

    /// The same actor volume at the resolved stance. A Notary keeps its box.
    pub fn actor_stance(
        self,
        feet: [f32; 3],
        identity: Option<CampaignActor>,
        ducking: bool,
        range: f32,
    ) -> Option<SurfaceHit> {
        if is_notary(identity) {
            return self.actor(feet, identity, range);
        }
        self.fighter_with_height(
            feet,
            crate::movement::RADIUS,
            body_height(identity, ducking),
            range,
        )
    }
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
    #[cfg(test)]
    pub fn fighter(self, feet: [f32; 3], radius: f32, range: f32) -> Option<SurfaceHit> {
        self.fighter_with_height(feet, radius, FIGHTER_HEIGHT, range)
    }

    pub fn fighter_with_height(
        self,
        feet: [f32; 3],
        radius: f32,
        height: f32,
        range: f32,
    ) -> Option<SurfaceHit> {
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
            feet[1] + height,
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
    fn a_channeling_auditor_is_engaged_before_any_nearer_hostile() {
        let union = |kind, phase| {
            Some(CampaignActor::Union {
                kind,
                phase,
                phase_started: 0,
                phase_ends: 0,
                seated: false,
            })
        };
        let channel = union(EnemyKind::Auditor, crate::protocol::EnemyPhase::Channeling);
        let idle = union(EnemyKind::Auditor, crate::protocol::EnemyPhase::Idle);
        let sweeper = union(EnemyKind::Sweeper, crate::protocol::EnemyPhase::Windup);
        assert!(channeling(channel));
        assert!(!channeling(idle) && !channeling(sweeper) && !channeling(None));
        let far_channel = engagement_key(channel, 15.0);
        let near_sweeper = engagement_key(sweeper, 3.0);
        assert!(engagement_before(far_channel, near_sweeper));
        assert!(!engagement_before(near_sweeper, far_channel));
        assert!(engagement_before(near_sweeper, engagement_key(idle, 4.0)));
        assert!(!engagement_before(far_channel, far_channel));
    }

    #[test]
    fn fighter_shots_aim_at_the_chest() {
        let union = |kind| {
            Some(CampaignActor::Union {
                kind,
                phase: crate::protocol::EnemyPhase::Idle,
                phase_started: 0,
                phase_ends: 0,
                seated: false,
            })
        };
        assert_eq!(aim_height(None), TORSO_HEIGHT);
        const {
            assert!(TORSO_HEIGHT > FIGHTER_HEIGHT * 0.5 + 0.2);
            assert!(TORSO_HEIGHT < FIGHTER_HEIGHT);
            assert!(HEAD_GATE > TORSO_HEIGHT);
            assert!(HEAD_GATE < crate::movement::EYE_HEIGHT);
            assert!(HEAD_GATE < FIGHTER_HEIGHT);
        };
        assert!(head_hit(0.0, crate::movement::EYE_HEIGHT, None));
        assert!(!head_hit(0.0, TORSO_HEIGHT, None));
        assert_eq!(
            traced_damage(crate::protocol::WeaponType::Rail, 80, true),
            160
        );
        assert_eq!(
            traced_damage(crate::protocol::WeaponType::Fists, 20, true),
            20
        );
        assert_eq!(
            traced_damage(crate::protocol::WeaponType::Shiv, 35, true),
            35
        );
        assert!(!head_hit(0.0, FIGHTER_HEIGHT + 0.2, None));
        let crawler = union(EnemyKind::Crawler);
        assert!(!head_hit(0.0, CRAWLER_HEIGHT * 0.5, crawler));
        assert!(head_hit(0.0, CRAWLER_HEIGHT * 0.9, crawler));
        let notary = union(EnemyKind::Notary);
        assert!(!head_hit(0.0, NOTARY_HEIGHT * 0.5, notary));
        assert!(head_hit(0.0, NOTARY_HEIGHT * 0.9, notary));
        assert_eq!(aim_height(union(EnemyKind::Crawler)), CRAWLER_HEIGHT * 0.5);
        assert_eq!(aim_height(union(EnemyKind::Notary)), NOTARY_HEIGHT * 0.5);
        assert_eq!(aim_point([3.0, 0.0, 4.0], None), [3.0, TORSO_HEIGHT, 4.0]);

        let feet = [8.0, 0.0, 0.0];
        let eye = [0.0, crate::movement::EYE_HEIGHT, 0.0];
        assert_eq!(shot_aim(feet, None, eye, &[]), [8.0, TORSO_HEIGHT, 0.0]);
        // At the midpoint the chest ray is near 1.41 and the hip ray near 1.25.
        let breastplate = Solid::from_center_volume(4.0, 0.0, 0.15, 1.0, 1.32, 1.55);
        assert_eq!(
            shot_aim(feet, None, eye, &[breastplate]),
            [8.0, FIGHTER_HEIGHT * 0.5, 0.0],
            "a gap under the breastplate still counts"
        );
        let counter = Solid::from_center_volume(4.0, 0.0, 0.15, 1.0, 1.20, 1.32);
        assert_eq!(
            shot_aim(feet, None, eye, &[counter]),
            [8.0, FIGHTER_HEIGHT * 0.5, 0.0],
            "a counter that stops the hips still stops the shot"
        );
        let low = Solid::from_center_volume(4.0, 0.0, 0.15, 1.0, 0.0, 0.7);
        assert_eq!(
            shot_aim(feet, None, eye, &[low]),
            [8.0, TORSO_HEIGHT, 0.0],
            "an open chest above a low obstacle is the aim"
        );
        // The belt ray clears this counter. The bottom of a scatter cone does not,
        // so the shot stays on the hips instead of skipping the lip.
        let lip = Solid::from_center_volume(4.0, 0.0, 0.15, 1.0, 0.0, 1.10);
        assert_eq!(
            shot_aim(feet, None, eye, &[lip]),
            [8.0, FIGHTER_HEIGHT * 0.5, 0.0],
            "a belt line that only just clears a lip does not lift the shot"
        );
        let wall = Solid::from_center(4.0, 0.0, 0.15, 1.0);
        assert_eq!(
            shot_aim(feet, None, eye, &[wall]),
            [8.0, FIGHTER_HEIGHT * 0.5, 0.0],
            "cover that hides the whole body keeps the shot on the hip line"
        );
        let crawler = union(EnemyKind::Crawler);
        assert_eq!(
            shot_aim(feet, crawler, eye, &[breastplate]),
            [8.0, CRAWLER_HEIGHT * 0.5, 0.0]
        );
    }

    #[test]
    fn a_ducked_fighter_lowers_the_head_band_and_the_chest() {
        let drop = crate::movement::BODY_HEIGHT - crate::movement::DUCK_HEIGHT;
        assert!((drop - 0.45).abs() < 0.001);
        assert!(
            !head_hit_for(0.0, crate::movement::EYE_HEIGHT, None, true),
            "a standing eye ray passes over the short body"
        );
        assert!(
            head_hit_for(0.0, TORSO_HEIGHT, None, true),
            "a standing chest aim is a headshot on a ducked body"
        );
        assert!(
            !head_hit_for(0.0, TORSO_HEIGHT - drop, None, true),
            "the ducked chest stays a body shot"
        );
        assert_eq!(
            aim_point_for([3.0, 0.0, 4.0], None, true),
            [3.0, TORSO_HEIGHT - drop, 4.0]
        );
        assert_eq!(
            aim_point_for([3.0, 0.0, 4.0], None, false),
            aim_point([3.0, 0.0, 4.0], None)
        );
        assert_eq!(stance_eye(None, true), crate::movement::DUCK_EYE_HEIGHT);
        assert_eq!(stance_eye(None, false), crate::movement::EYE_HEIGHT);
        let crawler = Some(CampaignActor::Union {
            kind: EnemyKind::Crawler,
            phase: crate::protocol::EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
        });
        assert_eq!(body_height(crawler, true), CRAWLER_HEIGHT);
        assert!(!head_hit_for(0.0, CRAWLER_HEIGHT * 0.5, crawler, true));
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
    fn low_crawler_requires_a_low_pellet_lane_and_cover_stops_it() {
        let feet = [4.0, 0.0, 0.0];
        let high = Ray::dispersed([0.0, 1.1, 0.0], 0.0, 0.0, 0.0, [0.5, 0.5]);
        assert!(high
            .fighter_with_height(feet, 0.5, CRAWLER_HEIGHT, 10.0)
            .is_none());
        let low = Ray::dispersed([0.0, 0.4, 0.0], 0.0, 0.0, 0.0, [0.5, 0.5]);
        let body = low
            .fighter_with_height(feet, 0.5, CRAWLER_HEIGHT, 10.0)
            .unwrap();
        assert!((body.distance - 3.5).abs() < 0.0001);
        let spread_pellet = Ray::dispersed([0.0, 0.4, 0.0], 0.0, 0.0, 0.08, [0.1, 0.5]);
        assert!(spread_pellet
            .fighter_with_height(feet, 0.5, CRAWLER_HEIGHT, 10.0)
            .is_some());
        let cover = Solid {
            min_x: 2.0,
            max_x: 2.2,
            min_z: -1.0,
            max_z: 1.0,
            bottom: 0.0,
            top: 0.6,
        };
        assert!(
            low.solid(&cover, body.distance).is_some(),
            "low cover must block the pellet"
        );
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
