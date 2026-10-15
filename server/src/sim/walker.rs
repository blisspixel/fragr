//! Bounded artillery machine with committed tells and shared resolved damage.
use super::{grenade, GameState, PLAYER_FLOOR_Y};
use crate::combat::Ray;
use crate::maps::walker_solids_overlap as overlaps;
use crate::movement::{Arena, Solid};
use crate::protocol::{
    WalkerGeometry, WalkerPhase as Phase, WalkerShellState, WalkerState, WALKER_ARTILLERY_WARNING,
    WALKER_HP, WALKER_RECOVERY, WALKER_SHELLS, WALKER_SHELL_LIFE, WALKER_SHELL_RADIUS,
    WALKER_SPEED, WALKER_STOMP_RADIUS, WALKER_STOMP_WARNING,
};
use uuid::Uuid;

const GRAVITY: f32 = 12.0;
const FLIGHT_SECONDS: f32 = 1.5;

pub(crate) struct Walker {
    pub(crate) state: WalkerState,
    next_station: usize,
    requested_station: Option<usize>,
    fired: usize,
}

impl Walker {
    pub(crate) fn new(g: &WalkerGeometry) -> Self {
        Self {
            state: WalkerState {
                hp: WALKER_HP,
                stage: 1,
                phase: Phase::Dormant,
                phase_started: 0,
                phase_ends: 0,
                feet: g.stations[0],
                target: g.approach,
                artillery_targets: [g.approach; 3],
                shells_left: WALKER_SHELLS,
                shells: Vec::new(),
            },
            next_station: 0,
            requested_station: None,
            fired: 0,
        }
    }

    fn phase(&mut self, phase: Phase, tick: u64, duration: u64) {
        self.state.phase = phase;
        self.state.phase_started = tick;
        self.state.phase_ends = tick.saturating_add(duration);
    }

    fn hurt(&mut self, damage: i32, tick: u64) {
        if damage <= 0 || matches!(self.state.phase, Phase::Dormant | Phase::Disabled) {
            return;
        }
        self.state.hp = self.state.hp.saturating_sub(damage).max(0);
        self.state.stage = if self.state.hp > 600 {
            1
        } else if self.state.hp > 300 {
            2
        } else {
            3
        };
        if self.state.hp == 0 {
            // Shells already committed remain real until impact or reset.
            self.phase(Phase::Disabled, tick, 0);
            tracing::info!("Continuance Walker disabled");
        }
    }
}

impl GameState {
    pub(crate) fn request_walker_station(&mut self, index: usize) {
        if let Some(w) = self.walker.as_mut().filter(|w| w.state.hp > 0 && index < 3) {
            if w.state.phase == Phase::Relocating {
                w.next_station = index;
            } else {
                w.requested_station = Some(index);
            }
        }
    }
    pub(crate) fn walker_arena(&self) -> Option<Arena> {
        let g = self.map.walker_geometry()?;
        let walker = self.walker.as_ref()?;
        let mut arena = self.map.arena().clone();
        for &i in &g.solids {
            arena.solids[i] = g.translated(arena.solids[i], walker.state.feet);
        }
        Some(arena)
    }

    pub(super) fn damage_walker_shot(&mut self, shooter: Uuid, solid: usize, damage: i32) {
        if self.campaign_run_frozen()
            || !self.m14_walker_active()
            || !self.players.iter().any(|p| {
                p.id == shooter
                    && p.is_participant()
                    && !p.detached
                    && crate::mission::actor_active(self.mission.as_ref(), p.id, p.campaign)
            })
        {
            return;
        }
        let Some(g) = self.map.walker_geometry() else {
            return;
        };
        let Some(part) = g.solids.iter().position(|s| *s == solid) else {
            return;
        };
        let Some(w) = &mut self.walker else {
            return;
        };
        let damage = if part > 0 && w.state.phase == Phase::Recovery {
            damage
        } else {
            damage / 4
        };
        w.hurt(damage, self.tick);
    }

    /// One blast may touch several legs; it damages the machine only once.
    pub(super) fn damage_walker_blast(
        &mut self,
        owner: Uuid,
        position: [f32; 3],
        radius: f32,
        peak: f32,
        rocket_direct: Option<(usize, i32)>,
        arena: &Arena,
    ) {
        if self.campaign_run_frozen()
            || !self.m14_walker_active()
            || !self.players.iter().any(|p| {
                p.id == owner
                    && p.is_participant()
                    && crate::mission::actor_active(self.mission.as_ref(), p.id, p.campaign)
            })
        {
            return;
        }
        let Some(g) = self.map.walker_geometry() else {
            return;
        };
        let Some(w) = &mut self.walker else {
            return;
        };
        let mut amount = 0;
        for (part, &index) in g.solids.iter().enumerate() {
            let s = arena.solids[index];
            let point = [
                position[0].clamp(s.min_x, s.max_x),
                position[1].clamp(s.bottom, s.top),
                position[2].clamp(s.min_z, s.max_z),
            ];
            let distance = grenade::distance(position, point);
            let direction: [f32; 3] = std::array::from_fn(|i| position[i] - point[i]);
            // Stop just outside the target face so the target does not cover itself.
            let visible = if distance <= 0.0001 {
                position
            } else {
                std::array::from_fn(|i| point[i] + direction[i] / distance * 0.001)
            };
            if !crate::combat::line_of_sight(position, visible, &arena.solids) {
                continue;
            }
            let splash = (peak * (1.0 - distance / radius)).floor().max(0.0) as i32;
            let direct =
                if let Some((_, amount)) = rocket_direct.filter(|(solid, _)| *solid == index) {
                    if part > 0 && w.state.phase == Phase::Recovery {
                        amount
                    } else {
                        amount / 4
                    }
                } else {
                    0
                };
            amount = amount.max(splash + direct);
        }
        w.hurt(amount, self.tick);
    }

    pub(super) fn tick_walker(&mut self, dt: f32) {
        if self.campaign_run_frozen() || !self.m14_walker_active() {
            return;
        }
        let Some(g) = self.map.walker_geometry() else {
            return;
        };
        let Some(mut walker) = self.walker.take() else {
            return;
        };
        let tick = self.tick;
        let target = self
            .players
            .iter()
            .filter(|p| p.is_participant() && self.contact_eligible(p))
            .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
            .filter(|p| g.arena.contains(*p))
            .min_by(|a, b| {
                grenade::distance(*a, walker.state.feet)
                    .total_cmp(&grenade::distance(*b, walker.state.feet))
            });
        let mut arena = self.map.arena().clone();
        for &i in &g.solids {
            arena.solids[i] = g.translated(arena.solids[i], walker.state.feet);
        }
        self.advance_walker_shells(&mut walker, dt, &arena);
        match walker.state.phase {
            Phase::Dormant => {
                if self.players.iter().any(|p| {
                    p.is_participant()
                        && self.contact_eligible(p)
                        && g.activation.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])
                }) {
                    walker.phase(Phase::StompWarning, tick, WALKER_STOMP_WARNING);
                    tracing::info!("Continuance Walker activated; stomp warning");
                }
            }
            Phase::StompWarning if tick >= walker.state.phase_ends => {
                let mut centre = walker.state.feet;
                centre[1] += 0.15;
                self.walker_blast(centre, WALKER_STOMP_RADIUS, 55.0, &arena);
                walker.phase(Phase::Stomp, tick, 4);
            }
            Phase::Stomp if tick >= walker.state.phase_ends => {
                if let Some(target) = target.filter(|_| walker.state.shells_left > 0) {
                    walker.state.target = target;
                    let dx = target[0] - walker.state.feet[0];
                    let dz = target[2] - walker.state.feet[2];
                    let length = dx.hypot(dz).max(0.001);
                    for (i, mark) in walker.state.artillery_targets.iter_mut().enumerate() {
                        let offset = (i as f32 - 1.0) * 4.0;
                        *mark = [
                            (target[0] + dx / length * offset)
                                .clamp(g.arena.min[0], g.arena.max[0]),
                            target[1],
                            (target[2] + dz / length * offset)
                                .clamp(g.arena.min[2], g.arena.max[2]),
                        ];
                    }
                    walker.fired = 0;
                    walker.phase(Phase::ArtilleryWarning, tick, WALKER_ARTILLERY_WARNING);
                } else {
                    walker.phase(Phase::Recovery, tick, WALKER_RECOVERY);
                }
            }
            Phase::ArtilleryWarning if tick >= walker.state.phase_ends => {
                walker.phase(Phase::Artillery, tick, 16);
            }
            Phase::Artillery => {
                if walker.fired < 3 && tick >= walker.state.phase_started + walker.fired as u64 * 6
                {
                    if walker.state.shells_left > 0 && walker.state.shells.len() < 6 {
                        if let Some(id) = self.projectile_serial.checked_add(1) {
                            self.projectile_serial = id;
                            let body = arena.solids[g.solids[0]];
                            let origin =
                                [walker.state.feet[0], body.top + 0.3, walker.state.feet[2]];
                            let target = walker.state.artillery_targets[walker.fired];
                            let mut velocity =
                                std::array::from_fn(|i| (target[i] - origin[i]) / FLIGHT_SECONDS);
                            velocity[1] += GRAVITY * FLIGHT_SECONDS * 0.5;
                            walker.state.shells.push(WalkerShellState {
                                id,
                                position: origin,
                                velocity,
                                age_ticks: 0,
                            });
                            walker.state.shells_left -= 1;
                        }
                    }
                    walker.fired += 1;
                }
                if tick >= walker.state.phase_ends {
                    walker.next_station = walker
                        .requested_station
                        .take()
                        .unwrap_or((walker.next_station + 1) % 3);
                    walker.phase(Phase::Relocating, tick, 400);
                }
            }
            Phase::Relocating => {
                let destination = g.stations[walker.next_station];
                let dx = destination[0] - walker.state.feet[0];
                let dz = destination[2] - walker.state.feet[2];
                let distance = dx.hypot(dz);
                let step = (WALKER_SPEED * dt.clamp(0.0, crate::movement::DT_LIVE)).min(distance);
                let next = if distance <= 0.001 {
                    destination
                } else {
                    [
                        walker.state.feet[0] + dx / distance * step,
                        0.0,
                        walker.state.feet[2] + dz / distance * step,
                    ]
                };
                let blocked = self.walker_step_blocked(&g, walker.state.feet, next);
                if !blocked {
                    walker.state.feet = next;
                }
                // An occupant or wreck can refuse the whole move, but cannot
                // remove the promised recovery window or stall the fight.
                if blocked || distance <= step + 0.001 || tick >= walker.state.phase_ends {
                    walker.phase(Phase::Recovery, tick, WALKER_RECOVERY);
                }
            }
            Phase::Recovery if tick >= walker.state.phase_ends => {
                walker.phase(Phase::StompWarning, tick, WALKER_STOMP_WARNING);
            }
            _ => {}
        }
        self.walker = Some(walker);
    }

    fn walker_step_blocked(&self, g: &WalkerGeometry, old: [f32; 3], next: [f32; 3]) -> bool {
        g.solids.iter().any(|&i| {
            let initial = self.map.arena().solids[i];
            let a = g.translated(initial, old);
            let b = g.translated(initial, next);
            let swept = Solid {
                min_x: a.min_x.min(b.min_x),
                max_x: a.max_x.max(b.max_x),
                min_z: a.min_z.min(b.min_z),
                max_z: a.max_z.max(b.max_z),
                ..a
            };
            self.players
                .iter()
                .filter(|p| self.contact_eligible(p))
                .any(|p| {
                    let r = crate::movement::RADIUS;
                    overlaps(
                        swept,
                        Solid {
                            min_x: p.x - r,
                            max_x: p.x + r,
                            min_z: p.z - r,
                            max_z: p.z + r,
                            bottom: p.y - PLAYER_FLOOR_Y,
                            top: p.y - PLAYER_FLOOR_Y
                                + crate::combat::body_height(p.campaign, p.ducking),
                        },
                    )
                })
                || self
                    .vehicles
                    .iter()
                    .any(|v| overlaps(swept, crate::vehicles::hull(&v.state)))
        })
    }

    fn walker_blast(&mut self, position: [f32; 3], radius: f32, peak: f32, arena: &Arena) {
        let Some(id) = self.projectile_serial.checked_add(1) else {
            return;
        };
        self.projectile_serial = id;
        self.resolve_blast(
            &grenade::Blast {
                id,
                owner_id: Uuid::nil(),
                position,
                radius,
                peak,
                source: grenade::BlastSource::Walker,
            },
            arena,
        );
    }

    fn advance_walker_shells(&mut self, walker: &mut Walker, dt: f32, arena: &Arena) {
        let dt = if dt.is_finite() {
            dt.clamp(0.0, crate::movement::DT_LIVE) / 4.0
        } else {
            0.0
        };
        let mut surviving = Vec::new();
        for mut shell in std::mem::take(&mut walker.state.shells) {
            let mut impact = None;
            for _ in 0..4 {
                let displacement: [f32; 3] = std::array::from_fn(|i| {
                    shell.velocity[i] * dt - if i == 1 { 0.5 * GRAVITY * dt * dt } else { 0.0 }
                });
                let distance = displacement.iter().map(|v| v * v).sum::<f32>().sqrt();
                if distance <= f32::EPSILON {
                    continue;
                }
                let ray = Ray {
                    origin: shell.position,
                    direction: displacement.map(|v| v / distance),
                };
                let mut hit = grenade::first_contact(&ray, distance, arena).map(|h| h.distance);
                for v in &self.vehicles {
                    if let Some(h) = ray.solid(&crate::vehicles::hull(&v.state), distance) {
                        hit = Some(hit.map_or(h.distance, |d| d.min(h.distance)));
                    }
                }
                for p in self.players.iter().filter(|p| self.contact_eligible(p)) {
                    if let Some(h) = ray.fighter_with_height(
                        [p.x, p.y - PLAYER_FLOOR_Y, p.z],
                        crate::movement::RADIUS,
                        crate::combat::body_height(p.campaign, p.ducking),
                        distance,
                    ) {
                        hit = Some(hit.map_or(h.distance, |d| d.min(h.distance)));
                    }
                }
                if let Some(distance) = hit {
                    impact = Some(ray.point((distance - grenade::CONTACT_EPSILON).max(0.0)));
                    break;
                }
                shell.position = ray.point(distance);
                shell.velocity[1] -= GRAVITY * dt;
            }
            shell.age_ticks += 1;
            if let Some(position) = impact {
                self.resolve_blast(
                    &grenade::Blast {
                        id: shell.id,
                        owner_id: Uuid::nil(),
                        position,
                        radius: WALKER_SHELL_RADIUS,
                        peak: 60.0,
                        source: grenade::BlastSource::Walker,
                    },
                    arena,
                );
            } else if shell.age_ticks < WALKER_SHELL_LIFE {
                surviving.push(shell);
            }
        }
        walker.state.shells = surviving;
    }
}

#[cfg(test)]
mod tests;
