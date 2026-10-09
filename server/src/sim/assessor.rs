//! Finite, ballistic Assessor attacks. Rendering never resolves an impact.
use super::{grenade, GameState, PLAYER_FLOOR_Y};
use crate::combat::Ray;
use crate::movement::{Arena, Solid};
use crate::protocol::AssessorCanisterState;
use uuid::Uuid;

pub(crate) const SPEED: f32 = 12.0;
pub(crate) const GRAVITY: f32 = 4.0;
pub(crate) const LIFE_TICKS: u32 = 80;
const SUBSTEPS: usize = 4;

pub(super) struct Canister {
    id: u32,
    owner_id: Uuid,
    position: [f32; 3],
    velocity: [f32; 3],
    launched_at: u64,
    age_ticks: u32,
}
impl Canister {
    pub(super) fn owner_id(&self) -> Uuid {
        self.owner_id
    }
}

/// Low-angle root at a fixed speed. The committed point is never refreshed.
pub(crate) fn launch_velocity(origin: [f32; 3], target: [f32; 3]) -> Option<[f32; 3]> {
    if !origin.iter().chain(&target).all(|v| v.is_finite()) {
        return None;
    }
    let delta: [f32; 3] = std::array::from_fn(|i| target[i] - origin[i]);
    let horizontal = delta[0].hypot(delta[2]);
    if !(0.1..=24.0).contains(&horizontal) {
        return None;
    }
    let speed2 = SPEED * SPEED;
    let discriminant =
        speed2 * speed2 - GRAVITY * (GRAVITY * horizontal * horizontal + 2.0 * delta[1] * speed2);
    if discriminant < 0.0 {
        return None;
    }
    let angle = ((speed2 - discriminant.sqrt()) / (GRAVITY * horizontal)).atan();
    let planar = SPEED * angle.cos();
    Some([
        delta[0] / horizontal * planar,
        SPEED * angle.sin(),
        delta[2] / horizontal * planar,
    ])
}

impl GameState {
    pub(crate) fn has_assessor_canister(&self, id: Uuid) -> bool {
        self.assessor_canisters.iter().any(|c| c.owner_id == id)
    }

    pub(super) fn assessor_canister_states(&self) -> Vec<AssessorCanisterState> {
        self.assessor_canisters
            .iter()
            .map(|c| AssessorCanisterState {
                id: c.id,
                owner_id: c.owner_id,
                position: c.position,
                velocity: c.velocity,
                age_ticks: c.age_ticks,
            })
            .collect()
    }

    pub(super) fn launch_assessor_canister(&mut self, id: Uuid) -> bool {
        if self.assessor_canisters.len() >= 64
            || self
                .assessor_canisters
                .iter()
                .filter(|c| c.owner_id == id)
                .count()
                >= 6
        {
            return false;
        }
        let Some(player) = self
            .players
            .iter()
            .find(|p| p.id == id && p.hp > 0 && crate::combat::is_assessor(p.campaign))
        else {
            return false;
        };
        if !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign) {
            return false;
        }
        let origin = [
            player.x,
            player.y - PLAYER_FLOOR_Y + crate::combat::ASSESSOR_HEIGHT * 0.5,
            player.z,
        ];
        let Some(target) = self.encounters.assessor_target(id) else {
            return false;
        };
        let Some(velocity) = launch_velocity(origin, target) else {
            return false;
        };
        if !grenade::clear_sphere(origin, &self.current_arena()) {
            return false;
        }
        let Some(serial) = self.projectile_serial.checked_add(1) else {
            return false;
        };
        if !self.encounters.spend_assessor_canister(id) {
            return false;
        }
        self.projectile_serial = serial;
        self.assessor_canisters.push(Canister {
            id: serial,
            owner_id: id,
            position: origin,
            velocity,
            launched_at: self.tick,
            age_ticks: 0,
        });
        true
    }

    pub(crate) fn resolve_assessor_wreck(&mut self, id: Uuid) {
        let Some(player) = self
            .players
            .iter()
            .find(|p| p.id == id && p.hp <= 0 && crate::combat::is_assessor(p.campaign))
        else {
            return;
        };
        let position = [
            player.x,
            player.y - PLAYER_FLOOR_Y + grenade::RADIUS,
            player.z,
        ];
        let Some(serial) = self.projectile_serial.checked_add(1) else {
            return;
        };
        self.projectile_serial = serial;
        let arena = self.current_arena().into_owned();
        self.resolve_blast(
            &grenade::Blast {
                id: serial,
                owner_id: id,
                position,
                radius: 1.5,
                peak: 45.0,
                source: grenade::BlastSource::AssessorWreck,
            },
            &arena,
        );
        let killed: Vec<Uuid> = self
            .explosion_results
            .iter()
            .rev()
            .find(|result| result.id == serial)
            .map(|result| {
                result
                    .hits
                    .iter()
                    .filter(|hit| hit.killed)
                    .map(|hit| hit.target_id)
                    .collect()
            })
            .unwrap_or_default();
        self.note_m12_assessor_wreck(id, serial, &killed);
    }

    pub(super) fn tick_assessor_canisters(
        &mut self,
        dt: f32,
        arena: &Arena,
        civilians: &[crate::movement::contact::ContactBody],
        tableau: &[Solid],
    ) {
        let delta = if dt.is_finite() {
            dt.clamp(0.0, crate::movement::DT_LIVE) / SUBSTEPS as f32
        } else {
            0.0
        };
        let mut next = Vec::with_capacity(self.assessor_canisters.len());
        for mut canister in std::mem::take(&mut self.assessor_canisters) {
            if canister.launched_at == self.tick {
                next.push(canister);
                continue;
            }
            let mut impact = None;
            for _ in 0..SUBSTEPS {
                let displacement: [f32; 3] = std::array::from_fn(|i| {
                    canister.velocity[i] * delta
                        - if i == 1 {
                            0.5 * GRAVITY * delta * delta
                        } else {
                            0.0
                        }
                });
                let length = displacement.iter().map(|v| v * v).sum::<f32>().sqrt();
                if length <= f32::EPSILON {
                    continue;
                }
                let ray = Ray {
                    origin: canister.position,
                    direction: displacement.map(|v| v / length),
                };
                let mut contact = grenade::first_contact(&ray, length, arena).map(|h| h.distance);
                let mut test_solid = |solid: &Solid| {
                    if let Some(hit) = ray.solid(&expanded(solid), length) {
                        contact = Some(contact.map_or(hit.distance, |d| d.min(hit.distance)));
                    }
                };
                for vehicle in &self.vehicles {
                    test_solid(&crate::vehicles::hull(&vehicle.state));
                }
                for body in tableau {
                    test_solid(body);
                }
                for body in civilians {
                    if let Some(hit) = ray.fighter_with_height(
                        [body.from.x, body.from.y - grenade::RADIUS, body.from.z],
                        body.radius + grenade::RADIUS,
                        body.height + 2.0 * grenade::RADIUS,
                        length,
                    ) {
                        contact = Some(contact.map_or(hit.distance, |d| d.min(hit.distance)));
                    }
                }
                for player in &self.players {
                    if player.id == canister.owner_id || !self.contact_eligible(player) {
                        continue;
                    }
                    let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
                    let hit =
                        if let Some(radius) = crate::combat::flying_half_width(player.campaign) {
                            ray.solid(
                                &expanded(&Solid {
                                    min_x: feet[0] - radius,
                                    max_x: feet[0] + radius,
                                    min_z: feet[2] - radius,
                                    max_z: feet[2] + radius,
                                    bottom: feet[1],
                                    top: feet[1] + crate::combat::target_height(player.campaign),
                                }),
                                length,
                            )
                        } else {
                            ray.fighter_with_height(
                                [feet[0], feet[1] - grenade::RADIUS, feet[2]],
                                crate::movement::RADIUS + grenade::RADIUS,
                                crate::combat::body_height(player.campaign, player.ducking)
                                    + 2.0 * grenade::RADIUS,
                                length,
                            )
                        };
                    if let Some(hit) = hit {
                        contact = Some(contact.map_or(hit.distance, |d| d.min(hit.distance)));
                    }
                }
                if let Some(distance) = contact {
                    impact = Some(ray.point((distance - grenade::CONTACT_EPSILON).max(0.0)));
                    break;
                }
                canister.position = ray.point(length);
                canister.velocity[1] -= GRAVITY * delta;
            }
            canister.age_ticks += 1;
            if let Some(position) = impact {
                self.resolve_blast(
                    &grenade::Blast {
                        id: canister.id,
                        owner_id: canister.owner_id,
                        position,
                        radius: 3.0,
                        peak: 45.0,
                        source: grenade::BlastSource::AssessorCanister,
                    },
                    arena,
                );
            } else if canister.age_ticks < LIFE_TICKS {
                next.push(canister);
            }
        }
        self.assessor_canisters = next;
    }
}

fn expanded(s: &Solid) -> Solid {
    let r = grenade::RADIUS;
    Solid {
        min_x: s.min_x - r,
        max_x: s.max_x + r,
        min_z: s.min_z - r,
        max_z: s.max_z + r,
        bottom: s.bottom - r,
        top: s.top + r,
    }
}

#[cfg(test)]
mod tests;
