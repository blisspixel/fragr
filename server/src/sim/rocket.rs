//! Straight rockets. The server owns flight, impact and splash.
use super::{grenade, GameState, PLAYER_FLOOR_Y};
use crate::combat::Ray;
use crate::movement::{Arena, Solid};
use crate::protocol::ShotImpact;
use crate::protocol::{ExplosionHit, ExplosionResult, RocketState, WeaponType};
use uuid::Uuid;

pub(crate) const SPEED: f32 = 18.0;
pub(crate) const LIFE_TICKS: u32 = 80;
const SUBSTEPS: usize = 4;
const DIRECT: i32 = 65;
const SPLASH_PEAK: f32 = 45.0;
const SPLASH_RADIUS: f32 = 4.0;
const MAX_LIVE: usize = 64;
const MAX_PER_OWNER: usize = 8;

pub(super) struct Rocket {
    id: u32,
    pub(super) owner_id: Uuid,
    position: [f32; 3],
    velocity: [f32; 3],
    launched_at: u64,
    age_ticks: u32,
    /// The eye opened inside a solid. Detonate there on the launch tick.
    blocked_origin: bool,
}

#[derive(Clone, Copy)]
enum Direct {
    Player { index: usize, normal: [f32; 3] },
    Vehicle { index: usize },
}

impl GameState {
    pub(super) fn rocket_states(&self) -> Vec<RocketState> {
        self.rockets
            .iter()
            .map(|rocket| RocketState {
                id: rocket.id,
                owner_id: rocket.owner_id,
                position: rocket.position,
                velocity: rocket.velocity,
                age_ticks: rocket.age_ticks,
            })
            .collect()
    }

    /// Caps and the serial are checked before ammunition or statistics change.
    pub(super) fn launch_rocket(&mut self, id: Uuid) -> bool {
        let Some(index) = self
            .players
            .iter()
            .position(|player| player.id == id && player.hp > 0)
        else {
            return false;
        };
        let player = &self.players[index];
        if player.weapon != WeaponType::Rocket
            || !player.yaw.is_finite()
            || !player.pitch.is_finite()
        {
            return false;
        }
        if !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign) {
            return false;
        }
        if self.rockets.len() >= MAX_LIVE
            || self
                .rockets
                .iter()
                .filter(|rocket| rocket.owner_id == id)
                .count()
                >= MAX_PER_OWNER
        {
            return false;
        }
        let Some(serial) = self.projectile_serial.checked_add(1) else {
            return false;
        };
        let origin = [
            player.x,
            player.y - PLAYER_FLOOR_Y + crate::combat::stance_eye(player.campaign, player.ducking),
            player.z,
        ];
        let velocity = [
            player.yaw.cos() * player.pitch.cos() * SPEED,
            player.pitch.sin() * SPEED,
            player.yaw.sin() * player.pitch.cos() * SPEED,
        ];
        if !origin
            .iter()
            .chain(&velocity)
            .all(|value| value.is_finite())
        {
            return false;
        }
        let dry_before = self.players[index].inventory.dry_fire_count();
        if !self.players[index].inventory.try_fire(WeaponType::Rocket) {
            if self.players[index].inventory.dry_fire_count() > dry_before {
                self.players[index].statistics.dry_trigger();
            }
            return false;
        }
        let arena = self.current_arena();
        let blocked_origin = !grenade::clear_sphere(origin, &arena);
        self.projectile_serial = serial;
        self.rockets.push(Rocket {
            id: serial,
            owner_id: id,
            position: origin,
            velocity,
            launched_at: self.tick,
            age_ticks: 0,
            blocked_origin,
        });
        let player = &mut self.players[index];
        player.statistics.attack(WeaponType::Rocket);
        player.just_fired = true;
        player.fire_cooldown = WeaponType::Rocket.cooldown_ticks();
        true
    }

    pub(super) fn tick_rockets(
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
        let mut next = Vec::with_capacity(self.rockets.len());
        for mut rocket in std::mem::take(&mut self.rockets) {
            if rocket.launched_at == self.tick {
                if rocket.blocked_origin {
                    let position = rocket.position;
                    self.resolve_rocket(&rocket, position, position, None, arena);
                } else {
                    next.push(rocket);
                }
                continue;
            }
            let mut impact: Option<([f32; 3], [f32; 3], Option<Direct>)> = None;
            for _ in 0..SUBSTEPS {
                let displacement: [f32; 3] = rocket.velocity.map(|value| value * delta);
                let length = displacement
                    .iter()
                    .map(|value| value * value)
                    .sum::<f32>()
                    .sqrt();
                if length <= f32::EPSILON {
                    continue;
                }
                let ray = Ray {
                    origin: rocket.position,
                    direction: displacement.map(|value| value / length),
                };
                if let Some((distance, direct)) = self.earliest_rocket_contact(
                    &ray,
                    length,
                    arena,
                    civilians,
                    tableau,
                    rocket.owner_id,
                ) {
                    let position = ray.point((distance - grenade::CONTACT_EPSILON).max(0.0));
                    impact = Some((rocket.position, position, direct));
                    break;
                }
                rocket.position = ray.point(length);
            }
            rocket.age_ticks += 1;
            if let Some((from, position, direct)) = impact {
                self.resolve_rocket(&rocket, from, position, direct, arena);
            } else if rocket.age_ticks < LIFE_TICKS {
                next.push(rocket);
            }
        }
        self.rockets = next;
    }

    fn earliest_rocket_contact(
        &self,
        ray: &Ray,
        length: f32,
        arena: &Arena,
        civilians: &[crate::movement::contact::ContactBody],
        tableau: &[Solid],
        owner_id: Uuid,
    ) -> Option<(f32, Option<Direct>)> {
        let mut best: Option<(f32, Option<Direct>)> = None;
        let consider =
            |best: &mut Option<(f32, Option<Direct>)>, distance: f32, direct: Option<Direct>| {
                if best.as_ref().is_none_or(|(current, _)| distance < *current) {
                    *best = Some((distance, direct));
                }
            };
        for (index, player) in self.players.iter().enumerate() {
            if player.id == owner_id || !self.contact_eligible(player) {
                continue;
            }
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            let hit = if let Some(radius) = crate::combat::flying_half_width(player.campaign) {
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
                consider(
                    &mut best,
                    hit.distance,
                    Some(Direct::Player {
                        index,
                        normal: hit.normal,
                    }),
                );
            }
        }
        for (index, vehicle) in self.vehicles.iter().enumerate() {
            if vehicle.state.hp <= 0 {
                continue;
            }
            if let Some(hit) = ray.solid(&expanded(&crate::vehicles::hull(&vehicle.state)), length)
            {
                consider(&mut best, hit.distance, Some(Direct::Vehicle { index }));
            }
        }
        for body in civilians {
            if let Some(hit) = ray.fighter_with_height(
                [body.from.x, body.from.y - grenade::RADIUS, body.from.z],
                body.radius + grenade::RADIUS,
                body.height + 2.0 * grenade::RADIUS,
                length,
            ) {
                consider(&mut best, hit.distance, None);
            }
        }
        for body in tableau {
            if let Some(hit) = ray.solid(&expanded(body), length) {
                consider(&mut best, hit.distance, None);
            }
        }
        if let Some(hit) = grenade::first_contact(ray, length, arena) {
            consider(&mut best, hit.distance, None);
        }
        best
    }

    fn resolve_rocket(
        &mut self,
        rocket: &Rocket,
        from: [f32; 3],
        position: [f32; 3],
        direct: Option<Direct>,
        arena: &Arena,
    ) {
        let Some(owner) = self
            .players
            .iter()
            .position(|player| player.id == rocket.owner_id)
        else {
            return;
        };
        let mut planned = Vec::new();
        for target in 0..self.players.len() {
            if planned.len() == 256 {
                break;
            }
            let player = &self.players[target];
            if player.hp <= 0
                || !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign)
            {
                continue;
            }
            let mut damage = 0;
            let mut contact = false;
            if let Some(Direct::Player { index, normal }) = direct {
                if index == target {
                    damage = self.plated_direct_damage(
                        target,
                        DIRECT,
                        from,
                        &ShotImpact::Fighter { normal },
                    );
                    contact = true;
                }
            }
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            let point =
                grenade::closest_body_point_stance(position, feet, player.campaign, player.ducking);
            let distance = grenade::distance(position, point);
            let splash = (SPLASH_PEAK * (1.0 - distance / SPLASH_RADIUS)).floor() as i32;
            if splash > 0 && crate::combat::line_of_sight(position, point, &arena.solids) {
                damage += splash;
            }
            if contact || damage > 0 {
                planned.push((target, damage, contact));
            }
        }
        let mut hits = Vec::new();
        let (mut hp_total, mut armor_total, mut kills) = (0u64, 0u64, 0u64);
        let mut connect = false;
        for (target, damage, contact) in planned {
            let (hp, armor, died) = if damage > 0 {
                self.resolve_fighter_hit_for(owner, target, damage, None, false)
            } else {
                (0, 0, false)
            };
            if contact || hp + armor > 0 {
                connect = true;
            }
            hp_total += hp;
            armor_total += armor;
            kills += u64::from(died);
            if hp + armor > 0 {
                let player = &self.players[target];
                hits.push(ExplosionHit {
                    target_id: player.id,
                    hp_damage: hp as u32,
                    armor_damage: armor as u32,
                    target_hp_after: player.hp,
                    killed: died,
                });
            }
        }
        let mut hulls = Vec::new();
        for (index, jeep) in self.vehicles.iter().enumerate() {
            if jeep.state.hp <= 0 {
                continue;
            }
            let mut amount = 0;
            if let Some(Direct::Vehicle { index: hit }) = direct {
                if hit == index {
                    amount += DIRECT;
                }
            }
            let point = [
                jeep.state.position[0],
                jeep.state.position[1] + 0.7,
                jeep.state.position[2],
            ];
            let distance = grenade::distance(position, point);
            let splash = (SPLASH_PEAK * (1.0 - distance / SPLASH_RADIUS)).floor() as i32;
            if splash > 0 && crate::combat::line_of_sight(position, point, &arena.solids) {
                amount += splash;
            }
            if amount > 0 {
                hulls.push((jeep.state.id, amount));
            }
        }
        let owner_id = rocket.owner_id;
        for (id, amount) in hulls {
            self.damage_vehicle(id, amount, Some(owner_id));
        }
        if let Some(player) = self.players.iter_mut().find(|player| player.id == owner_id) {
            player.statistics.hit(
                WeaponType::Rocket,
                hp_total,
                armor_total,
                kills,
                connect,
                false,
            );
        }
        self.explosion_results.push(ExplosionResult {
            id: rocket.id,
            owner_id,
            position,
            radius: SPLASH_RADIUS,
            hits,
        });
    }
}

fn expanded(solid: &Solid) -> Solid {
    let radius = grenade::RADIUS;
    Solid {
        min_x: solid.min_x - radius,
        max_x: solid.max_x + radius,
        min_z: solid.min_z - radius,
        max_z: solid.max_z + radius,
        bottom: solid.bottom - radius,
        top: solid.top + radius,
    }
}

#[cfg(test)]
mod tests;
