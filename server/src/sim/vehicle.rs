use super::{GameState, PLAYER_FLOOR_Y};
use crate::movement::{Arena, Solid, BODY_HEIGHT, RADIUS};
use crate::protocol::{VehicleSeat, VehicleState};
use crate::vehicles::{self, VehicleInput};
use uuid::Uuid;
#[cfg(test)]
mod boarding_tests;
#[cfg(test)]
mod tests;

impl GameState {
    pub fn vehicle_seat(&self, id: Uuid) -> Option<(usize, VehicleSeat)> {
        self.vehicles
            .iter()
            .enumerate()
            .find_map(|(index, jeep)| jeep.state.seat(id).map(|seat| (index, seat)))
    }

    pub(crate) fn reset_vehicles(&mut self) {
        self.vehicles = self
            .map
            .vehicle_spawns()
            .into_iter()
            .enumerate()
            .filter(|(_, (kind, position, yaw))| {
                vehicles::clear_kind(*kind, *position, *yaw, self.map.arena())
            })
            .map(|(index, (kind, position, yaw))| {
                vehicles::Jeep::of_kind(index as u32 + 1, kind, position, yaw)
            })
            .take(crate::protocol::MAX_VEHICLES)
            .collect();
    }

    pub fn add_jeep(&mut self, position: [f32; 3], yaw: f32) -> Option<u32> {
        if self.vehicles.len() >= crate::protocol::MAX_VEHICLES
            || !vehicles::clear_body(position, yaw, &self.current_arena())
        {
            return None;
        }
        let id = self
            .vehicles
            .iter()
            .map(|v| v.state.id)
            .max()
            .unwrap_or(0)
            .checked_add(1)?;
        self.vehicles.push(vehicles::Jeep::new(id, position, yaw));
        Some(id)
    }

    pub(crate) fn vehicle_facts(&self) -> Vec<VehicleState> {
        self.vehicles
            .iter()
            .map(|jeep| {
                let mut state = jeep.state.clone();
                let live = |id| {
                    self.players
                        .iter()
                        .any(|p| p.id == id && self.contact_eligible(p))
                };
                state.driver = state.driver.filter(|id| live(*id));
                state.gunner = state.gunner.filter(|id| live(*id));
                state
            })
            .collect()
    }

    /// A seat transition moves a full body. Eye visibility alone can pass
    /// above low cover or below a slab while the occupant crosses through it.
    fn vehicle_passage_clear(
        &self,
        index: usize,
        from: [f32; 3],
        to: [f32; 3],
        arena: &Arena,
    ) -> bool {
        let blocked = |solid: &Solid| vehicles::body_passage_blocked(from, to, solid);
        !arena.solids.iter().any(blocked)
            && !self
                .vehicles
                .iter()
                .enumerate()
                .any(|(other, vehicle)| other != index && blocked(&vehicles::hull(&vehicle.state)))
    }

    fn exit_point(&self, index: usize, actor: Uuid, arena: &Arena) -> Option<[f32; 3]> {
        let jeep = &self.vehicles[index].state;
        let seat_feet = vehicles::seat_feet(jeep, jeep.seat(actor)?);
        let radii = if jeep.kind == crate::protocol::VehicleKind::LightAircraft {
            [6.0, 7.0, 8.5]
        } else {
            [2.5, 3.5, 5.0]
        };
        for radius in radii {
            for angle in [
                std::f32::consts::FRAC_PI_2,
                -std::f32::consts::FRAC_PI_2,
                0.0,
                std::f32::consts::PI,
            ] {
                let mut p =
                    vehicles::local_point(jeep.position, jeep.yaw + angle, [radius, 0.0, 0.0]);
                p[1] = arena.support_height(p[0], p[2], jeep.position[1] + 0.6);
                if let Some((level, _)) = vehicles::surface_at(self.map.water_regions(), p[0], p[2])
                {
                    p[1] = p[1].max(level - crate::movement::water::SWIM_DRAFT);
                }
                if p[0].abs() > arena.half - RADIUS
                    || p[2].abs() > arena.half - RADIUS
                    || (p[1] - jeep.position[1]).abs() > 1.5
                    || arena.blocked_body_at(p[0], p[2], p[1], p[1])
                {
                    continue;
                }
                if !self.vehicle_passage_clear(index, seat_feet, p, arena) {
                    continue;
                }
                if self.players.iter().any(|other| {
                    other.id != actor
                        && self.contact_eligible(other)
                        && (other.y - PLAYER_FLOOR_Y - p[1]).abs() < BODY_HEIGHT
                        && (other.x - p[0]).hypot(other.z - p[2]) < RADIUS * 2.0 + 0.05
                }) {
                    continue;
                }
                return Some(p);
            }
        }
        None
    }

    fn exit_vehicle(&mut self, index: usize, actor: Uuid, arena: &Arena) -> bool {
        let Some(point) = self.exit_point(index, actor, arena) else {
            return false;
        };
        self.vehicles[index].release(actor);
        if let Some(p) = self.players.iter_mut().find(|p| p.id == actor) {
            p.x = point[0];
            p.y = point[1] + PLAYER_FLOOR_Y;
            p.z = point[2];
            p.vy = 0.0;
            p.clear_input();
        }
        true
    }

    fn vehicle_interactions(&mut self, arena: &Arena) {
        let requests: Vec<_> = self
            .players
            .iter()
            .filter(|p| self.contact_eligible(p))
            .map(|p| (p.id, p.interaction_requested, p.pending_action.seat))
            .collect();
        for (actor, interact, switch) in requests {
            if let Some(p) = self.players.iter_mut().find(|p| p.id == actor) {
                p.pending_action.seat = None;
            }
            if let Some((index, seat)) = self.vehicle_seat(actor) {
                if let Some(p) = self.players.iter_mut().find(|p| p.id == actor) {
                    p.interaction_requested = false;
                }
                if self.vehicles[index].state.speed.abs() > vehicles::ENTRY_SPEED {
                    continue;
                }
                if interact {
                    self.exit_vehicle(index, actor, arena);
                    continue;
                }
                if let Some(next) = switch.filter(|next| *next != seat) {
                    let jeep = &mut self.vehicles[index];
                    if jeep.state.hp > 0
                        && vehicles::supports_seat(jeep.state.kind, next)
                        && self.tick >= jeep.state.control_ready_tick
                        && jeep.occupant(next).is_none()
                    {
                        jeep.release(actor);
                        jeep.assign(next, Some(actor));
                        jeep.state.control_ready_tick = self.tick + vehicles::SWITCH_TICKS;
                    }
                }
                continue;
            }
            if !interact {
                continue;
            }
            let Some(p) = self
                .players
                .iter()
                .find(|p| p.id == actor && p.is_participant())
            else {
                continue;
            };
            let candidate = self
                .vehicles
                .iter()
                .enumerate()
                .filter(|(_, v)| {
                    v.state.hp > 0
                        && v.state.speed.abs() <= vehicles::ENTRY_SPEED
                        && (p.y - PLAYER_FLOOR_Y - v.state.position[1]).abs() <= 2.0
                        && (p.x - v.state.position[0]).hypot(p.z - v.state.position[2])
                            <= vehicles::entry_radius(v.state.kind)
                })
                .filter_map(|(index, v)| {
                    let occupied = v.state.driver.or(v.state.gunner);
                    if occupied
                        .and_then(|id| self.players.iter().find(|other| other.id == id))
                        .is_some_and(|other| {
                            p.team.is_some() && other.team.is_some() && p.team != other.team
                        })
                    {
                        return None;
                    }
                    let seat = if v.state.driver.is_none() {
                        VehicleSeat::Driver
                    } else if v.state.gunner.is_none()
                        && vehicles::supports_seat(v.state.kind, VehicleSeat::Gunner)
                    {
                        VehicleSeat::Gunner
                    } else {
                        return None;
                    };
                    if !self.vehicle_passage_clear(
                        index,
                        [p.x, p.y - PLAYER_FLOOR_Y, p.z],
                        vehicles::seat_feet(&v.state, seat),
                        arena,
                    ) {
                        return None;
                    }
                    Some((
                        index,
                        seat,
                        (p.x - v.state.position[0]).hypot(p.z - v.state.position[2]),
                    ))
                })
                .min_by(|a, b| a.2.total_cmp(&b.2));
            if let Some((index, seat, _)) = candidate {
                self.vehicles[index].assign(seat, Some(actor));
                if let Some(p) = self.players.iter_mut().find(|p| p.id == actor) {
                    p.interaction_requested = false;
                    p.reset_movement_baseline();
                }
            }
        }
    }

    pub(super) fn tick_vehicles(&mut self, dt: f32, arena: &Arena) {
        if self.vehicles.is_empty() {
            return;
        }
        let live: Vec<_> = self
            .players
            .iter()
            .filter(|p| self.contact_eligible(p))
            .map(|p| p.id)
            .collect();
        for jeep in &mut self.vehicles {
            jeep.state.driver = jeep.state.driver.filter(|id| live.contains(id));
            jeep.state.gunner = jeep.state.gunner.filter(|id| live.contains(id));
            jeep.cool();
        }
        self.vehicle_interactions(arena);
        for index in 0..self.vehicles.len() {
            let jeep = &mut self.vehicles[index];
            jeep.abandoned_ticks = if jeep.state.driver.is_none() && jeep.state.gunner.is_none() {
                jeep.abandoned_ticks.saturating_add(1)
            } else {
                0
            };
            if jeep.abandoned_ticks >= 600
                && (jeep.state.hp == 0 || jeep.state.position != jeep.spawn.position)
            {
                let spawn = jeep.spawn;
                let mut clear = arena.clone();
                for (other, vehicle) in self.vehicles.iter().enumerate() {
                    if other != index {
                        clear.solids.push(vehicles::hull(&vehicle.state));
                    }
                }
                for p in self.players.iter().filter(|p| self.contact_eligible(p)) {
                    clear.solids.push(Solid {
                        min_x: p.x - RADIUS,
                        max_x: p.x + RADIUS,
                        min_z: p.z - RADIUS,
                        max_z: p.z + RADIUS,
                        bottom: p.y - PLAYER_FLOOR_Y,
                        top: p.y - PLAYER_FLOOR_Y + BODY_HEIGHT,
                    });
                }
                if vehicles::clear_kind(
                    self.vehicles[index].state.kind,
                    spawn.position,
                    spawn.yaw,
                    &clear,
                ) {
                    self.vehicles[index] = vehicles::Jeep::of_kind(
                        self.vehicles[index].state.id,
                        self.vehicles[index].state.kind,
                        spawn.position,
                        spawn.yaw,
                    );
                }
            }
            if self.vehicles[index].state.hp <= 0 {
                if self.vehicles[index].state.kind == crate::protocol::VehicleKind::LightAircraft {
                    let mut falling = self.vehicles[index].motion();
                    falling.speed = 0.0;
                    falling = vehicles::vehicle_step_kind(
                        crate::protocol::VehicleKind::LightAircraft,
                        falling,
                        VehicleInput::default(),
                        dt,
                        arena,
                        self.map.water_regions(),
                    );
                    self.vehicles[index].apply_motion(falling);
                }
                if self.vehicles[index].state.burning_ticks > 0 {
                    self.vehicles[index].state.burning_ticks -= 1;
                    if self.vehicles[index].state.burning_ticks == 0 {
                        let occupants = [
                            self.vehicles[index].state.driver,
                            self.vehicles[index].state.gunner,
                        ];
                        for actor in occupants.into_iter().flatten() {
                            if !self.exit_vehicle(index, actor, arena) {
                                // A burning wreck cannot hold a living occupant forever.
                                // No clear exit means destruction in place, never teleportation.
                                if let Some(victim) =
                                    self.players.iter().position(|p| p.id == actor)
                                {
                                    let attacker = self.vehicles[index]
                                        .last_attacker
                                        .and_then(|id| self.players.iter().position(|p| p.id == id))
                                        .filter(|attacker| self.damage_lands(*attacker, victim))
                                        .filter(|_| {
                                            !self
                                                .spawn_shields
                                                .get(&actor)
                                                .is_some_and(|ticks| *ticks > 0)
                                        })
                                        .unwrap_or(victim);
                                    let damage = self.players[victim].hp.max(0)
                                        + self.players[victim].armor.max(0);
                                    self.resolve_fighter_hit(attacker, victim, damage, None);
                                }
                                self.vehicles[index].release(actor);
                            }
                        }
                        let state = self.vehicles[index].state.clone();
                        let owner = self.vehicles[index].last_attacker.unwrap_or(Uuid::nil());
                        self.projectile_serial = self.projectile_serial.saturating_add(1);
                        self.resolve_blast(
                            &super::grenade::Blast {
                                id: self.projectile_serial,
                                owner_id: owner,
                                position: [
                                    state.position[0],
                                    state.position[1] + 0.7,
                                    state.position[2],
                                ],
                                radius: 5.0,
                                peak: 120.0,
                                source: super::grenade::BlastSource::Vehicle,
                            },
                            arena,
                        );
                    }
                }
                continue;
            }
            let driver = self.vehicles[index].state.driver;
            let input = driver
                .and_then(|id| self.players.iter().find(|p| p.id == id))
                .filter(|_| self.tick >= self.vehicles[index].state.control_ready_tick)
                .map(|p| VehicleInput {
                    forward: p.pending_action.forward,
                    back: p.pending_action.back,
                    left: p.pending_action.left,
                    right: p.pending_action.right,
                    brake: p.pending_action.jump || p.jump_requested,
                    descend: p.pending_action.duck,
                })
                .unwrap_or_default();
            let mut collision = arena.clone();
            for (other, jeep) in self.vehicles.iter().enumerate() {
                if other != index {
                    collision.solids.push(vehicles::hull(&jeep.state));
                }
            }
            let before = self.vehicles[index].motion();
            let kind = self.vehicles[index].state.kind;
            let proposed = vehicles::vehicle_step_kind(
                kind,
                before,
                input,
                dt,
                &collision,
                self.map.water_regions(),
            );
            if before.speed.abs() > 6.0 {
                if let Some(driver_index) =
                    driver.and_then(|id| self.players.iter().position(|p| p.id == id))
                {
                    let first = self
                        .players
                        .iter()
                        .enumerate()
                        .filter(|(_, p)| {
                            self.contact_eligible(p) && self.vehicle_seat(p.id).is_none()
                        })
                        .filter_map(|(victim, p)| {
                            vehicle_contact(
                                kind,
                                before,
                                proposed,
                                [p.x, p.y - PLAYER_FLOOR_Y, p.z],
                                crate::combat::body_height(p.campaign, p.ducking),
                            )
                            .map(|t| (victim, t))
                        })
                        .min_by(|a, b| a.1.total_cmp(&b.1));
                    if let Some((victim, _)) = first.filter(|(victim, _)| {
                        let same_side = self.players[driver_index].team.is_some()
                            && self.players[driver_index].team == self.players[*victim].team;
                        !same_side && self.damage_lands(driver_index, *victim)
                    }) {
                        self.resolve_fighter_hit(
                            driver_index,
                            victim,
                            ((before.speed.abs() - 6.0) * 15.0) as i32,
                            None,
                        );
                    }
                }
            }
            for p in &self.players {
                if self.contact_eligible(p) && self.vehicle_seat(p.id).is_none() {
                    collision.solids.push(Solid {
                        min_x: p.x - RADIUS,
                        max_x: p.x + RADIUS,
                        min_z: p.z - RADIUS,
                        max_z: p.z + RADIUS,
                        bottom: p.y - PLAYER_FLOOR_Y,
                        top: p.y - PLAYER_FLOOR_Y
                            + crate::combat::body_height(p.campaign, p.ducking),
                    });
                }
            }
            let after = vehicles::vehicle_step_kind(
                kind,
                before,
                input,
                dt,
                &collision,
                self.map.water_regions(),
            );
            self.vehicles[index].apply_motion(after);
            let water_crash = kind == crate::protocol::VehicleKind::LightAircraft
                && vehicles::surface_at(
                    self.map.water_regions(),
                    after.position[0],
                    after.position[2],
                )
                .is_some_and(|(level, _)| after.position[1] <= level + 0.1);
            let hard_landing = kind == crate::protocol::VehicleKind::LightAircraft
                && before.vy < -4.0
                && after.vy == 0.0;
            if water_crash
                || hard_landing
                || (kind == crate::protocol::VehicleKind::LightAircraft
                    && before.speed > 6.0
                    && after.speed == 0.0)
            {
                self.vehicles[index].damage(400, driver);
            } else if before.speed.abs() > 6.0 && after.speed == 0.0 {
                self.vehicles[index].damage(((before.speed.abs() - 6.0) * 8.0) as i32, driver);
            }
        }
        self.follow_vehicle_seats();
    }

    pub(super) fn follow_vehicle_seats(&mut self) {
        for jeep in &self.vehicles {
            for (seat, actor) in [
                (VehicleSeat::Driver, jeep.state.driver),
                (VehicleSeat::Gunner, jeep.state.gunner),
            ] {
                if let Some(p) = actor.and_then(|id| self.players.iter_mut().find(|p| p.id == id)) {
                    let feet = vehicles::seat_feet(&jeep.state, seat);
                    p.x = feet[0];
                    p.y = feet[1] + PLAYER_FLOOR_Y;
                    p.z = feet[2];
                    p.vy = jeep.state.vy;
                    p.ducking = seat == VehicleSeat::Driver;
                    p.last_movement_tick = None;
                    p.throw_requested = false;
                    p.place_requested = false;
                    p.remote_place_requested = false;
                    p.remote_trigger_requested = false;
                    p.reload_requested = false;
                }
            }
        }
    }

    pub(super) fn damage_vehicle(&mut self, id: u32, damage: i32, attacker: Option<Uuid>) {
        if let Some(jeep) = self.vehicles.iter_mut().find(|v| v.state.id == id) {
            jeep.damage(damage, attacker);
        }
    }

    pub(super) fn blast_vehicles(&mut self, blast: &super::grenade::Blast, arena: &Arena) {
        for jeep in &mut self.vehicles {
            let point = [
                jeep.state.position[0],
                jeep.state.position[1] + 0.7,
                jeep.state.position[2],
            ];
            let distance = super::grenade::distance(blast.position, point);
            let damage = (blast.peak * (1.0 - distance / blast.radius)).floor() as i32;
            if damage > 0 && crate::combat::line_of_sight(blast.position, point, &arena.solids) {
                jeep.damage(damage, Some(blast.owner_id));
            }
        }
    }
}

fn vehicle_contact(
    kind: crate::protocol::VehicleKind,
    from: vehicles::VehicleMotion,
    to: vehicles::VehicleMotion,
    feet: [f32; 3],
    victim_height: f32,
) -> Option<f32> {
    let distance = (to.position[0] - from.position[0]).hypot(to.position[2] - from.position[2]);
    let steps = ((distance / 0.1).ceil() as usize).max(4);
    for step in 0..=steps {
        let t = step as f32 / steps as f32;
        let position = std::array::from_fn(|axis| {
            from.position[axis] + (to.position[axis] - from.position[axis]) * t
        });
        let [length, width, height] = vehicles::dimensions(kind);
        if feet[1] + victim_height <= position[1] || feet[1] >= position[1] + height {
            continue;
        }
        let yaw = from.yaw
            + crate::movement::normalize_yaw(to.yaw - from.yaw + std::f32::consts::PI) * t
            - std::f32::consts::PI * t;
        if [-(length - width).max(0.0), 0.0, (length - width).max(0.0)]
            .into_iter()
            .any(|offset| {
                let centre = vehicles::local_point(position, yaw, [offset, 0.0, 0.0]);
                (centre[0] - feet[0]).hypot(centre[2] - feet[2]) <= width + RADIUS
            })
        {
            return Some(t);
        }
    }
    None
}
