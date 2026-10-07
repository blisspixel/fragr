//! Placed proximity mines. Flight, sticking, arming and trips are server facts.
use super::grenade::{self, Blast, BlastSource};
use super::{GameState, PLAYER_FLOOR_Y};
use crate::movement::Arena;
use crate::protocol::{MinePhase, MineState};
use uuid::Uuid;

pub const PLACE_COOLDOWN: u32 = 15;
pub use crate::protocol::{MINE_ARMING_TICKS as ARMING_TICKS, MINE_TRIP_TICKS as TRIP_TICKS};
/// A body this close to an armed mine, with clear sight, trips it.
pub const TRIGGER_RADIUS: f32 = 2.0;
pub const BLAST_RADIUS: f32 = 4.5;
pub const BLAST_DAMAGE: f32 = 130.0;
pub const LIVE_PER_OWNER: usize = 3;
pub const LIVE_GLOBAL: usize = 32;
/// A mine that has not stuck within this many ticks is removed without a blast.
pub const FLIGHT_TICKS: u64 = 100;
const PLACE_SPEED: f32 = 8.0;
const PLACE_LIFT: f32 = 2.0;

pub(super) struct Mine {
    pub id: u32,
    pub owner_id: Uuid,
    position: [f32; 3],
    velocity: [f32; 3],
    normal: [f32; 3],
    phase: MinePhase,
    phase_started: u64,
    phase_ends: u64,
}

#[cfg(test)]
impl GameState {
    /// One live mine, so a map change can prove the world was cleared.
    pub(crate) fn test_insert_mine(&mut self, owner: Uuid) {
        self.mines.push(Mine {
            id: self.projectile_serial.wrapping_add(1),
            owner_id: owner,
            position: [1.0, 0.0, 1.0],
            velocity: [0.0, 0.0, 0.0],
            normal: [0.0, 1.0, 0.0],
            phase: MinePhase::Armed,
            phase_started: self.tick,
            phase_ends: self.tick,
        });
    }
}

impl GameState {
    pub(crate) fn clear_mines(&mut self) {
        self.mines.clear();
        for player in &mut self.players {
            player.place_requested = false;
            player.mine_cooldown = 0;
        }
    }

    pub(super) fn mine_states(&self) -> Vec<MineState> {
        self.mines
            .iter()
            .map(|mine| MineState {
                id: mine.id,
                owner_id: mine.owner_id,
                position: mine.position,
                normal: mine.normal,
                phase: mine.phase,
                phase_started: mine.phase_started,
                phase_ends: mine.phase_ends,
            })
            .collect()
    }

    /// Admit fresh placements. A placement consumes the tick's attack
    /// admission, like a throw; a refused one spends nothing.
    pub(super) fn place_mines(&mut self, launched: &[Uuid]) -> Vec<Uuid> {
        if !self.players.iter().any(|player| player.place_requested) {
            return Vec::new();
        }
        let arena = self.current_arena().into_owned();
        let mut placed = Vec::new();
        for player in &mut self.players {
            let requested = std::mem::take(&mut player.place_requested);
            if !requested
                || launched.contains(&player.id)
                || player.hp <= 0
                || player.detached
                || !player.is_participant()
                || player.mine_cooldown > 0
                || !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign)
                || self.mines.len() >= LIVE_GLOBAL
                || self
                    .mines
                    .iter()
                    .filter(|mine| mine.owner_id == player.id)
                    .count()
                    >= LIVE_PER_OWNER
            {
                continue;
            }
            let origin = [
                player.x,
                player.y - PLAYER_FLOOR_Y
                    + crate::combat::stance_eye(player.campaign, player.ducking),
                player.z,
            ];
            if !grenade::clear_sphere(origin, &arena)
                || !player.yaw.is_finite()
                || !player.pitch.is_finite()
            {
                continue;
            }
            let Some(serial) = self.projectile_serial.checked_add(1) else {
                continue;
            };
            if !player.inventory.try_place_mine() {
                continue;
            }
            self.projectile_serial = serial;
            let horizontal = player.pitch.cos() * PLACE_SPEED;
            self.mines.push(Mine {
                id: serial,
                owner_id: player.id,
                position: origin,
                velocity: [
                    player.yaw.cos() * horizontal,
                    player.pitch.sin() * PLACE_SPEED + PLACE_LIFT,
                    player.yaw.sin() * horizontal,
                ],
                normal: [0.0; 3],
                phase: MinePhase::Flying,
                phase_started: self.tick,
                phase_ends: self.tick,
            });
            player.mine_cooldown = PLACE_COOLDOWN;
            player.statistics.mine_attack();
            placed.push(player.id);
        }
        placed
    }

    pub(super) fn tick_mines(&mut self, dt: f32) {
        // A mine is an owned device: it goes dark with an absent or dead owner.
        let players = &self.players;
        self.mines.retain(|mine| {
            players
                .iter()
                .any(|p| p.id == mine.owner_id && p.hp > 0 && p.respawn_timer.is_none())
        });
        if self.mines.is_empty() {
            return;
        }
        let arena = self.current_arena().into_owned();
        let tick = self.tick;
        let mut live = std::mem::take(&mut self.mines);
        let mut removed = Vec::new();
        for mine in &mut live {
            match mine.phase {
                MinePhase::Flying => {
                    if mine.phase_started == tick {
                        continue;
                    }
                    if tick.saturating_sub(mine.phase_started) >= FLIGHT_TICKS {
                        removed.push(mine.id);
                        continue;
                    }
                    if let Some(normal) = fly(mine, dt.clamp(0.0, crate::movement::DT_LIVE), &arena)
                    {
                        mine.normal = normal;
                        mine.velocity = [0.0; 3];
                        mine.phase = MinePhase::Arming;
                        mine.phase_started = tick;
                        mine.phase_ends = tick.saturating_add(ARMING_TICKS);
                    }
                }
                MinePhase::Arming => {
                    if tick >= mine.phase_ends {
                        mine.phase = MinePhase::Armed;
                        mine.phase_started = tick;
                        mine.phase_ends = tick;
                    }
                }
                MinePhase::Armed => {
                    if self.mine_tripped(mine, &arena) {
                        mine.phase = MinePhase::Tripped;
                        mine.phase_started = tick;
                        mine.phase_ends = tick.saturating_add(TRIP_TICKS);
                    }
                }
                MinePhase::Tripped => {
                    if tick >= mine.phase_ends {
                        removed.push(mine.id);
                        self.resolve_blast(
                            &Blast {
                                id: mine.id,
                                owner_id: mine.owner_id,
                                position: mine.position,
                                radius: BLAST_RADIUS,
                                peak: BLAST_DAMAGE,
                                source: BlastSource::Mine,
                            },
                            &arena,
                        );
                    }
                }
            }
        }
        // Detonations and flights that never found a surface leave the world.
        live.retain(|mine| !removed.contains(&mine.id));
        // The blast may have killed an owner; their other mines go dark too.
        let players = &self.players;
        live.retain(|mine| {
            players
                .iter()
                .any(|p| p.id == mine.owner_id && p.hp > 0 && p.respawn_timer.is_none())
        });
        self.mines = live;
    }

    /// The owner, and any living active body the owner's damage would land
    /// on, trips an armed mine from inside the trigger radius in clear sight.
    fn mine_tripped(&self, mine: &Mine, arena: &Arena) -> bool {
        let Some(owner) = self.players.iter().position(|p| p.id == mine.owner_id) else {
            return false;
        };
        self.players.iter().enumerate().any(|(index, player)| {
            if player.hp <= 0
                || player.detached
                || !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign)
                || (index != owner && !self.damage_lands(owner, index))
            {
                return false;
            }
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            let point = grenade::closest_body_point(mine.position, feet, player.campaign);
            grenade::distance(mine.position, point) <= TRIGGER_RADIUS
                && crate::combat::line_of_sight(mine.position, point, &arena.solids)
        })
    }
}

/// One tick of flight. Returns the contact normal when the mine sticks.
fn fly(mine: &mut Mine, dt: f32, arena: &Arena) -> Option<[f32; 3]> {
    if !dt.is_finite() || dt <= 0.0 {
        return None;
    }
    for _ in 0..4 {
        let step = dt / 4.0;
        mine.velocity[1] -= crate::movement::GRAVITY * step;
        let length = mine.velocity.iter().map(|v| v * v).sum::<f32>().sqrt();
        if length <= f32::EPSILON {
            continue;
        }
        let range = length * step;
        let ray = crate::combat::Ray {
            origin: mine.position,
            direction: mine.velocity.map(|v| v / length),
        };
        let Some(hit) = grenade::first_contact(&ray, range, arena) else {
            mine.position = ray.point(range);
            continue;
        };
        mine.position = ray.point(hit.distance);
        for axis in 0..3 {
            mine.position[axis] += hit.normal[axis] * grenade::CONTACT_EPSILON;
        }
        return Some(hit.normal);
    }
    None
}

#[cfg(test)]
mod tests;
