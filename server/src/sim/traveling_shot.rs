//! A straight server-owned shot. It is a point on the combat ray, not a weapon
//! and not a body the movement model integrates.

use super::{GameState, PLAYER_FLOOR_Y};
use crate::combat::Ray;
use crate::protocol::ProjectileState;
use uuid::Uuid;

/// Half of `movement::TOP_SPEED`, so a walking fighter outruns the shot.
pub(crate) const SPEED: f32 = crate::movement::TOP_SPEED * 0.5;
/// Not the damage of any current weapon, so a hit cannot be mistaken for a gun.
pub(crate) const DAMAGE: i32 = 12;
/// Four seconds at 20 Hz: 10 metres at `SPEED`.
pub(crate) const LIFE_TICKS: u32 = 80;
/// Twelve seconds lets a pulse cross a yard while remaining easy to outrun.
pub(crate) const JAMMER_LIFE_TICKS: u32 = 240;

#[derive(Debug, Clone)]
pub(super) struct TravelingShot {
    pub id: u32,
    shooter_id: Uuid,
    position: [f32; 3],
    direction: [f32; 3],
    ticks_left: u32,
}

impl GameState {
    /// Launch one point from the shooter's eye along their current aim.
    /// A shooter who already has a shot in flight is refused. The direction
    /// does not change after this returns.
    pub fn launch_traveling_shot(&mut self, shooter_id: Uuid) -> bool {
        self.launch_point(shooter_id, LIFE_TICKS)
    }

    pub(super) fn launch_jammer_pulse(&mut self, shooter_id: Uuid) -> bool {
        self.launch_point(shooter_id, JAMMER_LIFE_TICKS)
    }

    pub(crate) fn has_traveling_shot(&self, shooter_id: Uuid) -> bool {
        self.traveling_shots
            .iter()
            .any(|shot| shot.shooter_id == shooter_id)
    }

    fn launch_point(&mut self, shooter_id: Uuid, ticks_left: u32) -> bool {
        if self.projectile_serial == u32::MAX
            || self
                .traveling_shots
                .iter()
                .any(|shot| shot.shooter_id == shooter_id)
        {
            return false;
        }
        let Some(shooter) = self.players.iter().find(|player| player.id == shooter_id) else {
            return false;
        };
        if shooter.hp <= 0
            || shooter.respawn_timer.is_some()
            || !crate::mission::actor_active(self.mission.as_ref(), shooter.id, shooter.campaign)
        {
            return false;
        }
        let Some(pitch) = crate::combat::clamp_pitch(shooter.pitch) else {
            return false;
        };
        let yaw = shooter.yaw;
        if !yaw.is_finite() {
            return false;
        }
        let (sy, cy) = yaw.sin_cos();
        let (sp, cp) = pitch.sin_cos();
        let origin = [
            shooter.x,
            shooter.y - PLAYER_FLOOR_Y + crate::combat::eye_height(shooter.campaign),
            shooter.z,
        ];
        if origin.iter().any(|value| !value.is_finite()) {
            return false;
        }
        self.projectile_serial += 1;
        self.traveling_shots.push(TravelingShot {
            id: self.projectile_serial,
            shooter_id,
            position: origin,
            direction: [cp * cy, sp, cp * sy],
            ticks_left,
        });
        true
    }

    pub(super) fn tick_traveling_shots(&mut self, dt: f32, arena: &crate::movement::Arena) {
        if self.traveling_shots.is_empty() {
            return;
        }
        let step = SPEED * dt;
        let mut next = Vec::with_capacity(self.traveling_shots.len());
        for mut shot in std::mem::take(&mut self.traveling_shots) {
            if !step.is_finite() || step <= 0.0 {
                shot.ticks_left = shot.ticks_left.saturating_sub(1);
                if shot.ticks_left > 0 {
                    next.push(shot);
                }
                continue;
            }
            let ray = Ray {
                origin: shot.position,
                direction: shot.direction,
            };
            let mut limit = step;
            let mut solid = false;
            if let Some(distance) = ray.floor(limit) {
                if distance <= limit {
                    limit = distance;
                    solid = true;
                }
            }
            for volume in &arena.solids {
                if let Some(hit) = ray.solid(volume, limit) {
                    if hit.distance <= limit {
                        limit = hit.distance;
                        solid = true;
                    }
                }
            }
            let mut victim: Option<usize> = None;
            for (index, target) in self.players.iter().enumerate() {
                if target.id == shot.shooter_id
                    || target.hp <= 0
                    || target.respawn_timer.is_some()
                    || target.is_campaign_companion()
                    || !crate::mission::actor_active(
                        self.mission.as_ref(),
                        target.id,
                        target.campaign,
                    )
                    || self
                        .spawn_shields
                        .get(&target.id)
                        .is_some_and(|ticks| *ticks > 0)
                {
                    continue;
                }
                let feet = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
                if let Some(hit) = ray.actor(feet, target.campaign, limit) {
                    if hit.distance <= limit {
                        limit = hit.distance;
                        solid = false;
                        victim = Some(index);
                    }
                }
            }
            if solid || victim.is_some() {
                if let Some(victim) = victim {
                    if let Some(shooter_idx) = self
                        .players
                        .iter()
                        .position(|player| player.id == shot.shooter_id)
                    {
                        let _ = self.resolve_fighter_hit(shooter_idx, victim, DAMAGE, None);
                    }
                }
                continue;
            }
            shot.position = ray.point(step);
            shot.ticks_left = shot.ticks_left.saturating_sub(1);
            if shot.ticks_left > 0 {
                next.push(shot);
            }
        }
        self.traveling_shots = next;
    }

    pub(super) fn projectile_states(&self) -> Vec<ProjectileState> {
        self.traveling_shots
            .iter()
            .map(|shot| ProjectileState {
                id: shot.id,
                x: shot.position[0],
                y: shot.position[1],
                z: shot.position[2],
            })
            .collect()
    }

    pub(crate) fn clear_traveling_shots(&mut self) {
        self.clear_grenades();
        self.clear_mines();
        self.traveling_shots.clear();
    }
}
