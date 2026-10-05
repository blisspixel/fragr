//! Counted, fixed-fuse explosives. Positions and impacts are server facts.
use super::{GameState, PLAYER_FLOOR_Y};
use crate::movement::{Arena, Solid};
use crate::protocol::{ExplosionHit, ExplosionResult, GrenadeState};
use uuid::Uuid;

pub const FUSE_TICKS: u32 = 40;
pub const THROW_COOLDOWN: u32 = 15;
pub const RADIUS: f32 = 0.12;
pub const BLAST_RADIUS: f32 = 4.0;
pub(super) const CONTACT_EPSILON: f32 = 0.0002;

/// One resolved detonation, shared by grenades and placed mines.
pub(super) struct Blast {
    pub id: u32,
    pub owner_id: Uuid,
    pub position: [f32; 3],
    pub radius: f32,
    /// Raw damage at the centre, falling linearly to zero at `radius`.
    pub peak: f32,
    pub source: BlastSource,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum BlastSource {
    Grenade,
    Mine,
    RemoteMine,
}

pub(super) struct Grenade {
    pub id: u32,
    pub owner_id: Uuid,
    position: [f32; 3],
    velocity: [f32; 3],
    fuse_ticks: u32,
    launched_at: u64,
    bounce_count: u32,
}

impl Grenade {
    fn blast(&self) -> Blast {
        Blast {
            id: self.id,
            owner_id: self.owner_id,
            position: self.position,
            radius: BLAST_RADIUS,
            peak: 100.0,
            source: BlastSource::Grenade,
        }
    }
}

#[cfg(test)]
impl GameState {
    fn resolve_explosion(&mut self, grenade: &Grenade, arena: &Arena) {
        self.resolve_blast(&grenade.blast(), arena);
    }

    /// A grenade-sized blast resolved against the current world, for tests
    /// outside the simulation module.
    pub(crate) fn test_blast(&mut self, owner: Uuid, position: [f32; 3], radius: f32, peak: f32) {
        let arena = self.current_arena().into_owned();
        self.resolve_blast(
            &Blast {
                id: u32::MAX,
                owner_id: owner,
                position,
                radius,
                peak,
                source: BlastSource::Grenade,
            },
            &arena,
        );
    }
}

impl GameState {
    pub(crate) fn clear_grenades(&mut self) {
        self.grenades.clear();
        self.explosion_results.clear();
        for player in &mut self.players {
            player.throw_requested = false;
            player.grenade_cooldown = 0;
        }
    }

    pub(super) fn grenade_states(&self) -> Vec<GrenadeState> {
        self.grenades
            .iter()
            .map(|grenade| GrenadeState {
                id: grenade.id,
                owner_id: grenade.owner_id,
                position: grenade.position,
                fuse_ticks: grenade.fuse_ticks,
                bounce_count: grenade.bounce_count,
            })
            .collect()
    }

    pub(super) fn launch_grenades(&mut self) -> Vec<Uuid> {
        if !self.players.iter().any(|player| player.throw_requested) {
            return Vec::new();
        }
        let arena = self.current_arena().into_owned();
        let mut launched = Vec::new();
        for player in &mut self.players {
            let requested = std::mem::take(&mut player.throw_requested);
            if !requested
                || player.hp <= 0
                || player.detached
                || !player.is_participant()
                || player.grenade_cooldown > 0
                || !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign)
                || self.grenades.len() >= 64
                || self
                    .grenades
                    .iter()
                    .filter(|g| g.owner_id == player.id)
                    .count()
                    >= 3
            {
                continue;
            }
            let origin = [
                player.x,
                player.y - PLAYER_FLOOR_Y + crate::combat::eye_height(player.campaign),
                player.z,
            ];
            if !clear_sphere(origin, &arena) || !player.yaw.is_finite() || !player.pitch.is_finite()
            {
                continue;
            }
            let Some(serial) = self.projectile_serial.checked_add(1) else {
                continue;
            };
            if !player.inventory.try_throw() {
                continue;
            }
            self.projectile_serial = serial;
            let horizontal = player.pitch.cos() * 12.0;
            self.grenades.push(Grenade {
                id: serial,
                owner_id: player.id,
                position: origin,
                velocity: [
                    player.yaw.cos() * horizontal,
                    player.pitch.sin() * 12.0 + 4.0,
                    player.yaw.sin() * horizontal,
                ],
                fuse_ticks: FUSE_TICKS,
                launched_at: self.tick,
                bounce_count: 0,
            });
            player.grenade_cooldown = THROW_COOLDOWN;
            player.statistics.grenade_attack();
            launched.push(player.id);
        }
        launched
    }

    pub(super) fn tick_grenades(&mut self, dt: f32) {
        if self.grenades.is_empty() {
            return;
        }
        let arena = self.current_arena().into_owned();
        let mut live = std::mem::take(&mut self.grenades);
        for grenade in &mut live {
            if grenade.launched_at == self.tick {
                continue;
            }
            // Public ticks are fixed-step; reject invalid diagnostic deltas rather
            // than feeding unbounded displacement into the contact solver.
            advance(grenade, dt.clamp(0.0, crate::movement::DT_LIVE), &arena);
            grenade.fuse_ticks = grenade.fuse_ticks.saturating_sub(1);
            if grenade.fuse_ticks == 0 {
                self.resolve_blast(&grenade.blast(), &arena);
            }
        }
        live.retain(|grenade| grenade.fuse_ticks > 0);
        self.grenades = live;
    }

    pub(super) fn resolve_blast(&mut self, blast: &Blast, arena: &Arena) {
        let Some(owner) = self
            .players
            .iter()
            .position(|player| player.id == blast.owner_id)
        else {
            return;
        };
        let mut hits = Vec::new();
        let (mut hp_total, mut armor_total, mut kills) = (0, 0, 0);
        for target in 0..self.players.len() {
            if hits.len() == 256 {
                break;
            }
            let player = &self.players[target];
            if player.hp <= 0
                || !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign)
                || (owner != target && !self.damage_lands(owner, target))
            {
                continue;
            }
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            let point = closest_body_point(blast.position, feet, player.campaign);
            let distance = distance(blast.position, point);
            let damage = (blast.peak * (1.0 - distance / blast.radius)).floor() as i32;
            if damage <= 0 || !crate::combat::line_of_sight(blast.position, point, &arena.solids) {
                continue;
            }
            let (hp, armor, died) = self.resolve_fighter_hit(owner, target, damage, None);
            if hp + armor == 0 {
                continue;
            }
            let player = &self.players[target];
            hits.push(ExplosionHit {
                target_id: player.id,
                hp_damage: hp as u32,
                armor_damage: armor as u32,
                target_hp_after: player.hp,
                killed: died,
            });
            if owner != target {
                hp_total += hp;
                armor_total += armor;
                kills += u64::from(died);
            }
        }
        let statistics = &mut self.players[owner].statistics;
        match blast.source {
            BlastSource::Grenade => statistics.grenade_hit(hp_total, armor_total, kills),
            BlastSource::Mine => statistics.mine_hit(hp_total, armor_total, kills),
            BlastSource::RemoteMine => statistics.remote_mine_hit(hp_total, armor_total, kills),
        }
        self.explosion_results.push(ExplosionResult {
            id: blast.id,
            owner_id: blast.owner_id,
            position: blast.position,
            radius: blast.radius,
            hits,
        });
    }
}

pub(super) fn distance(a: [f32; 3], b: [f32; 3]) -> f32 {
    a.iter()
        .zip(b)
        .map(|(a, b)| (a - b).powi(2))
        .sum::<f32>()
        .sqrt()
}

pub(super) fn closest_body_point(
    origin: [f32; 3],
    feet: [f32; 3],
    identity: Option<crate::protocol::CampaignActor>,
) -> [f32; 3] {
    let y = origin[1].clamp(feet[1], feet[1] + crate::combat::target_height(identity));
    if crate::combat::is_notary(identity) {
        let radius = crate::combat::NOTARY_HALF_WIDTH;
        return [
            origin[0].clamp(feet[0] - radius, feet[0] + radius),
            y,
            origin[2].clamp(feet[2] - radius, feet[2] + radius),
        ];
    }
    let dx = origin[0] - feet[0];
    let dz = origin[2] - feet[2];
    let scale = (crate::movement::RADIUS / dx.hypot(dz)).min(1.0);
    [feet[0] + dx * scale, y, feet[2] + dz * scale]
}

fn inflated(solid: &Solid) -> Solid {
    Solid {
        min_x: solid.min_x - RADIUS,
        max_x: solid.max_x + RADIUS,
        min_z: solid.min_z - RADIUS,
        max_z: solid.max_z + RADIUS,
        bottom: solid.bottom - RADIUS,
        top: solid.top + RADIUS,
    }
}

pub(super) fn clear_sphere(position: [f32; 3], arena: &Arena) -> bool {
    position.iter().all(|v| v.is_finite())
        && position[1] >= RADIUS
        && position[0].abs() <= arena.half - RADIUS
        && position[2].abs() <= arena.half - RADIUS
        && !arena
            .solids
            .iter()
            .any(|solid| inside(position, &inflated(solid)))
}

fn inside(p: [f32; 3], s: &Solid) -> bool {
    p[0] >= s.min_x
        && p[0] <= s.max_x
        && p[1] >= s.bottom
        && p[1] <= s.top
        && p[2] >= s.min_z
        && p[2] <= s.max_z
}

/// Earliest contact of a small sphere along `ray` within `range`: the
/// radius-expanded solids, the floor and the finite bounds.
pub(super) fn first_contact(
    ray: &crate::combat::Ray,
    range: f32,
    arena: &Arena,
) -> Option<crate::combat::SurfaceHit> {
    let mut contact = arena
        .solids
        .iter()
        .filter_map(|s| ray.solid(&inflated(s), range))
        .min_by(|a, b| a.distance.total_cmp(&b.distance));
    // Bounds and floor are finite inward-facing collision planes.
    for (axis, plane, normal_sign) in [
        (1, RADIUS, 1.0),
        (0, arena.half - RADIUS, -1.0),
        (0, -arena.half + RADIUS, 1.0),
        (2, arena.half - RADIUS, -1.0),
        (2, -arena.half + RADIUS, 1.0),
    ] {
        if ray.direction[axis] * normal_sign >= 0.0 {
            continue;
        }
        let t = (plane - ray.origin[axis]) / ray.direction[axis];
        if t >= 0.0 && t <= range && contact.is_none_or(|hit| t < hit.distance) {
            let mut normal = [0.0; 3];
            normal[axis] = normal_sign;
            contact = Some(crate::combat::SurfaceHit {
                distance: t,
                normal,
            });
        }
    }
    contact
}

fn advance(grenade: &mut Grenade, dt: f32, arena: &Arena) {
    if !dt.is_finite() || dt <= 0.0 {
        return;
    }
    // A moved tram can overtake a resting sphere. Hold it at its last pose
    // until clear rather than translating it through solid collision.
    if !clear_sphere(grenade.position, arena) {
        grenade.velocity = [0.0; 3];
        return;
    }
    for _ in 0..4 {
        let mut remaining = dt / 4.0;
        grenade.velocity[1] -= crate::movement::GRAVITY * remaining;
        for _ in 0..4 {
            let length = grenade.velocity.iter().map(|v| v * v).sum::<f32>().sqrt();
            if length <= f32::EPSILON {
                break;
            }
            let range = length * remaining;
            let ray = crate::combat::Ray {
                origin: grenade.position,
                direction: grenade.velocity.map(|v| v / length),
            };
            let Some(hit) = first_contact(&ray, range, arena) else {
                grenade.position = ray.point(range);
                break;
            };
            grenade.position = ray.point(hit.distance);
            for axis in 0..3 {
                grenade.position[axis] += hit.normal[axis] * CONTACT_EPSILON;
            }
            remaining *= (1.0 - hit.distance / range).clamp(0.0, 1.0);
            let normal_speed = grenade
                .velocity
                .iter()
                .zip(hit.normal)
                .map(|(v, n)| v * n)
                .sum::<f32>();
            // Supporting a settled sphere is not another audible bounce.
            if normal_speed.abs() >= 1.0 {
                grenade.bounce_count += 1;
            }
            for axis in 0..3 {
                grenade.velocity[axis] -= 1.45 * normal_speed * hit.normal[axis];
            }
            if hit.normal[1] > 0.5 {
                grenade.velocity[0] *= 0.72;
                grenade.velocity[2] *= 0.72;
                if grenade.velocity[1].abs() < 1.0 {
                    grenade.velocity[1] = 0.0;
                }
            }
            if remaining <= f32::EPSILON {
                break;
            }
        }
    }
}

#[cfg(test)]
mod tests;
