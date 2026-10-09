//! Placement against current authoritative cover and live bodies.
use super::*;
use crate::movement::{Arena, Solid, BODY_HEIGHT, CONTACT_EPSILON, RADIUS, STEP_UP};

type Spawn = (f32, f32, f32, f32);

struct Occupant {
    feet: [f32; 3],
    height: f32,
    eye: [f32; 3],
    hostile: bool,
}

fn fits(world: &Arena, (x, z, _, floor): Spawn) -> bool {
    x.abs() + RADIUS <= world.half
        && z.abs() + RADIUS <= world.half
        && !world.blocked_body_at(x, z, floor, floor)
}

fn fixed_fits(world: &Arena, hulls: &[Solid], (x, z, _, floor): Spawn) -> bool {
    // Established stair-edge bays use the ordinary walking step allowance.
    // A vehicle must still leave the entire standing spawn body clear.
    x.abs() + RADIUS <= world.half
        && z.abs() + RADIUS <= world.half
        && !world.blocked_body_at(x, z, floor, floor + STEP_UP)
        && !hulls.iter().any(|hull| {
            hull.top > floor
                && hull.bottom < floor + BODY_HEIGHT - CONTACT_EPSILON
                && hull.blocks(x, z, RADIUS)
        })
}

#[cfg(test)]
mod tests;

impl GameState {
    /// Prefer unoccupied slots, then fewer exposed firing lanes, then clearance.
    /// Cover matters even when the widest gap is inside another fighter's range.
    /// A lane only counts inside `SPAWN_THREAT_RANGE`: one longer than any
    /// weapon's reach must not push a respawn toward a closer covered corner.
    pub(super) fn select_spawn(
        &mut self,
        player_id: Uuid,
        team: Option<Team>,
        initial_angle: Option<f32>,
    ) -> Option<Spawn> {
        let mut world = self.current_arena().into_owned();
        let hulls: Vec<_> = self
            .vehicles
            .iter()
            .map(|vehicle| crate::vehicles::hull(&vehicle.state))
            .collect();
        world.solids.extend(hulls.iter().copied());
        if let Some(spawn) = initial_angle.map(|angle| self.map.spawn(angle)) {
            if fixed_fits(&world, &hulls, spawn) {
                return Some(spawn);
            }
        }
        let others: Vec<Occupant> = self
            .players
            .iter()
            .filter(|p| p.id != player_id && self.contact_eligible(p) && p.role != Role::Spectator)
            .map(|p| {
                let friendly = team.is_some() && p.team == team;
                Occupant {
                    feet: [p.x, p.y - PLAYER_FLOOR_Y, p.z],
                    height: crate::combat::body_height(p.campaign, p.ducking),
                    eye: [
                        p.x,
                        p.y - PLAYER_FLOOR_Y + crate::combat::stance_eye(p.campaign, p.ducking),
                        p.z,
                    ],
                    hostile: !friendly,
                }
            })
            .collect();
        let slots = self.map.spawn_slots();
        let angles: Vec<f32> = (0..slots)
            .map(|slot| slot as f32 * (2.0 * PI / slots as f32))
            .collect();
        // A side spawns in its own half of the map; a map without one falls
        // back to every slot rather than refusing to spawn.
        let own: Vec<f32> = team
            .map(|team| {
                angles
                    .iter()
                    .copied()
                    .filter(|angle| {
                        crate::rules::spawn_side(self.map.spawn(*angle).0) == Some(team)
                    })
                    .collect()
            })
            .unwrap_or_default();
        let own_half = !own.is_empty();
        let bases: Vec<Spawn> = if own_half { own } else { angles }
            .into_iter()
            .map(|angle| self.map.spawn(angle))
            .collect();
        let mut candidates: Vec<Spawn> = bases
            .iter()
            .copied()
            .filter(|spawn| fixed_fits(&world, &hulls, *spawn))
            .collect();
        // Keep the original bays whenever one still fits. A crowded motorpool
        // may block all of them, so try a small supported area in the same half.
        // This work is bounded by 24 samples per fixed bay, not a map search.
        if candidates.is_empty() {
            let arena = self.current_arena();
            for (x, z, yaw, floor) in bases {
                for radius in [2.0, 4.0, 6.0] {
                    for direction in 0..8 {
                        let angle = direction as f32 * PI / 4.0;
                        let (sx, sz) = (x + angle.cos() * radius, z + angle.sin() * radius);
                        if own_half && crate::rules::spawn_side(sx) != team {
                            continue;
                        }
                        let ground = arena.support_height(sx, sz, floor + STEP_UP);
                        let candidate = (sx, sz, yaw, ground);
                        if (ground - floor).abs() > STEP_UP || !fits(&world, candidate) {
                            continue;
                        }
                        let supported = [-RADIUS, RADIUS].into_iter().all(|dx| {
                            [-RADIUS, RADIUS].into_iter().all(|dz| {
                                (arena.support_height(sx + dx, sz + dz, ground + CONTACT_EPSILON)
                                    - ground)
                                    .abs()
                                    <= CONTACT_EPSILON
                            })
                        });
                        let submerged = self
                            .map
                            .water_regions()
                            .iter()
                            .any(|water| water.contains(sx, sz) && ground < water.level);
                        if supported && !submerged {
                            candidates.push(candidate);
                        }
                    }
                }
            }
        }
        if candidates.is_empty() {
            return None;
        }
        if others.is_empty() {
            if team.is_some() {
                let pick = self.next_u64() % candidates.len() as u64;
                return Some(candidates[pick as usize]);
            }
            let angle = self.next_f32() * 2.0 * PI;
            let spawn = self.map.spawn(angle);
            return Some(if fixed_fits(&world, &hulls, spawn) {
                spawn
            } else {
                candidates[0]
            });
        }
        let mut best_spawn = None;
        let mut best: Option<(bool, usize, f32)> = None;
        for spawn in candidates {
            let (sx, sz, _, floor) = spawn;
            let nearest = others
                .iter()
                .map(|other| (other.feet[0] - sx).hypot(other.feet[2] - sz))
                .fold(f32::MAX, f32::min);
            let clear = others.iter().all(|other| {
                other.feet[1] + other.height <= floor + CONTACT_EPSILON
                    || other.feet[1] >= floor + BODY_HEIGHT - CONTACT_EPSILON
                    || (other.feet[0] - sx).hypot(other.feet[2] - sz) >= PLAYER_RADIUS * 2.0
            });
            let exposed = others
                .iter()
                .filter(|other| other.hostile)
                .map(|other| other.eye)
                .filter(|&eye| {
                    // The longest weapon bounds relevant lanes even if the
                    // opponent swaps weapons immediately after this spawn.
                    (eye[0] - sx).hypot(eye[2] - sz) <= SPAWN_THREAT_RANGE
                        && [crate::combat::FIGHTER_HEIGHT * 0.5, EYE_HEIGHT]
                            .into_iter()
                            .any(|height| {
                                crate::combat::line_of_sight(
                                    eye,
                                    [sx, floor + height, sz],
                                    &world.solids,
                                )
                            })
                })
                .count();
            if best.is_none_or(|(was_clear, threats, gap)| {
                (clear && !was_clear)
                    || (clear == was_clear
                        && (exposed < threats || (exposed == threats && nearest > gap)))
            }) {
                best = Some((clear, exposed, nearest));
                best_spawn = Some(spawn);
            }
        }
        best_spawn
    }

    pub(super) fn do_respawn(&mut self, player_id: Uuid) {
        let team = self
            .players
            .iter()
            .find(|p| p.id == player_id)
            .and_then(|p| p.team);
        let Some((sx, sz, yaw, floor)) = self.select_spawn(player_id, team, None) else {
            if let Some(player) = self.players.iter_mut().find(|p| p.id == player_id) {
                player.hp = 0;
                player.respawn_timer = Some(1);
                player.clear_input();
            }
            self.spawn_shields.remove(&player_id);
            return;
        };
        if let Some(player) = self.players.iter_mut().find(|p| p.id == player_id) {
            player.reset_movement_baseline();

            player.x = sx;
            player.y = PLAYER_FLOOR_Y + floor;
            // A fighter that died mid-jump must not respawn still falling.
            player.vy = 0.0;
            player.z = sz;
            player.yaw = yaw;
            player.pitch = 0.0;
            player.ducking = false;
            player.hp = PLAYER_MAX_HP;
            player.armor = 0;
            player.respawn_timer = None;
            player.fire_cooldown = 0;
            player.repeater_cycle.reset();
            if let Some(weapon) = player.inventory.only() {
                player.weapon = weapon;
            }

            if self.map.equipment_policy() == crate::protocol::EquipmentPolicy::Discovery {
                let armed = player.inventory.armed();
                player.inventory = crate::inventory::Inventory::new(self.map.equipment_policy());
                if armed {
                    player.inventory.arm_magazines();
                }
                player.weapon = WeaponType::Fists;
                player.pending_action = Action::default();
                player.jump_requested = false;
                player.reload_requested = false;
                player.just_fired = false;
            } else {
                player.inventory.refill_if_armed();
            }

            self.events.push(GameEvent::Respawn {
                player: player.name.clone(),
            });
            self.spawn_shields.insert(player_id, SPAWN_SHIELD_TICKS);
        }
    }
}
