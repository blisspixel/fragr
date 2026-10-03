//! Roof, workshop and freight progression with optional grounded rescue.
use super::*;
use crate::protocol::{
    M05MapGeometry, M05ObjectiveState, M05TramPhase, M05TramState, M05WorkerState,
    MissionObjective, MissionObjectiveAction,
};
use std::borrow::Cow;
pub(crate) mod platform;

pub(super) struct M05Progress {
    pub(super) index: usize,
    pub(super) freight_open: bool,
    pub(super) group_released: bool,
    pub(super) captives: Vec<M05WorkerState>,
    pub(super) route_points: Vec<usize>,
    // Prefixes of the registered routes end at distinct physical berths. The
    // public geometry stays unchanged and clients validate the original paths.
    settling_routes: Vec<Vec<[f32; 3]>>,
    pub(super) tram: M05TramState,
    boarding_until: u64,
}
impl M05Progress {
    pub(super) fn new(g: M05MapGeometry) -> Self {
        let settling_routes = worker_settling_routes(&g);
        Self {
            index: 0,
            freight_open: false,
            group_released: false,
            route_points: vec![1; g.rescue.captives.len()],
            settling_routes,
            captives: g
                .rescue
                .captives
                .into_iter()
                .map(|c| M05WorkerState {
                    id: c.id,
                    feet: c.held,
                })
                .collect(),
            tram: M05TramState {
                phase: M05TramPhase::Parked,
                feet: g.tram.start,
                tick: 0,
            },
            boarding_until: 0,
        }
    }
}

fn worker_settling_routes(g: &M05MapGeometry) -> Vec<Vec<[f32; 3]>> {
    let mut routes: Vec<_> = g.rescue.captives.iter().map(|c| c.route.clone()).collect();
    let length = |route: &[[f32; 3]]| -> f32 {
        route
            .windows(2)
            .map(|p| (p[1][0] - p[0][0]).hypot(p[1][2] - p[0][2]))
            .sum()
    };
    let mut order: Vec<_> = (0..routes.len()).collect();
    order.sort_by(|&a, &b| {
        length(&routes[a])
            .total_cmp(&length(&routes[b]))
            .then_with(|| g.rescue.captives[a].id.cmp(&g.rescue.captives[b].id))
    });
    let mut berths: Vec<[f32; 3]> = Vec::new();
    for (rank, index) in order.into_iter().enumerate() {
        // Space along the route by more than the physical diameter, leaving
        // clearance around its final right-angle turn without lateral detours.
        let mut remaining = rank as f32 * crate::movement::RADIUS * 3.0;
        let route = &mut routes[index];
        for segment in (1..route.len()).rev() {
            let a = route[segment - 1];
            let b = route[segment];
            let distance = (b[0] - a[0]).hypot(b[2] - a[2]);
            if remaining > distance {
                remaining -= distance;
                continue;
            }
            let fraction = if distance > 0.0 {
                remaining / distance
            } else {
                0.0
            };
            let berth = std::array::from_fn(|i| b[i] + (a[i] - b[i]) * fraction);
            if g.boarding.contains(berth)
                && berths.iter().all(|old| {
                    (old[0] - berth[0]).hypot(old[2] - berth[2])
                        > crate::movement::RADIUS * 2.0 + crate::movement::contact::EPSILON
                })
            {
                route.truncate(segment + 1);
                route[segment] = berth;
                berths.push(berth);
            }
            break;
        }
    }
    routes
}
impl GameState {
    pub fn current_arena(&self) -> Cow<'_, crate::movement::Arena> {
        let Some(run) = &self.mission else {
            return Cow::Borrowed(self.map.arena());
        };
        let Some(p) = &run.m05 else {
            return Cow::Borrowed(self.map.arena());
        };
        let Some(prepared) = run.initial_map.m05_objectives() else {
            return Cow::Borrowed(self.map.arena());
        };
        let g = &prepared.geometry.tram;
        if p.tram.feet == g.start {
            return Cow::Borrowed(self.map.arena());
        }
        let mut arena = self.map.arena().clone();
        arena.solids[g.solid] = g.body(arena.solids[g.solid], p.tram.feet);
        Cow::Owned(arena)
    }
    pub(crate) fn ensure_m05_companion(&mut self) {
        if self
            .mission
            .as_ref()
            .is_some_and(|r| r.m05.is_some() && r.phase == MissionPhase::InProgress)
        {
            if let Some(g) = self.map.m05_geometry() {
                self.spawn_campaign_companion(g.companion_start, false);
            }
        }
    }
    pub(crate) fn m05_released_worker_ids(&self) -> Vec<String> {
        self.mission
            .as_ref()
            .and_then(|r| r.m05.as_ref())
            .filter(|p| p.group_released)
            .map_or_else(Vec::new, |p| {
                p.captives.iter().map(|c| c.id.clone()).collect()
            })
    }
    pub(crate) fn m05_evacuated_worker_ids(&self) -> Vec<String> {
        let Some(run) = &self.mission else {
            return Vec::new();
        };
        let Some(p) = run.m05.as_ref().filter(|p| p.group_released) else {
            return Vec::new();
        };
        let Some(g) = run.initial_map.m05_objectives() else {
            return Vec::new();
        };
        p.captives
            .iter()
            .filter(|c| g.geometry.boarding.contains(c.feet))
            .map(|c| c.id.clone())
            .collect()
    }
    pub(super) fn m05_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m05.as_ref()?;
        let prepared = run.initial_map.m05_objectives()?;
        let g = &prepared.geometry;
        let party: Vec<_> = self
            .players
            .iter()
            .filter(|p| p.is_participant())
            .map(|p| {
                let ready = run.ready.contains(&p.id);
                let alive = p.hp > 0 && p.respawn_timer.is_none();
                MissionMember {
                    id: p.id,
                    name: p.name.clone(),
                    ready,
                    alive,
                    aboard: run.phase != MissionPhase::Briefing
                        && ready
                        && alive
                        && g.boarding.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z]),
                }
            })
            .collect();
        let departed = run.phase == MissionPhase::Departed;
        let mut completed: Vec<String> = g
            .objectives
            .iter()
            .take(p.index.min(6))
            .map(|s| s.id.clone())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = if departed {
            None
        } else if p.index < 6 {
            Some(g.objectives[p.index].clone())
        } else {
            Some(MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: g.departure.clone(),
                },
            })
        };
        let ready = p.index == 6
            && p.freight_open
            && self.encounters.is_complete(prepared.departure_encounter)
            && !party.is_empty()
            && party.iter().all(|m| m.ready && m.alive && m.aboard);
        let arena = self.current_arena();
        let prompts =
            if ready && run.phase == MissionPhase::InProgress && !self.campaign_run_frozen() {
                self.players
                    .iter()
                    .filter(|p| {
                        p.is_participant()
                            && p.hp > 0
                            && p.respawn_timer.is_none()
                            && run.ready.contains(&p.id)
                            && can_use_in_arena(p, &g.departure, &self.map, &arena)
                    })
                    .map(|p| InteractionPrompt {
                        player_id: p.id,
                        kind: InteractionKind::ObjectiveUse,
                    })
                    .collect()
            } else {
                Vec::new()
            };
        Some(MissionState {
            id: MissionId::NoForwardingAddress,
            run: run.solo.as_ref().map(|s| s.state),
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            m02: None,
            m03: None,
            m04: None,
            m06: None,
            m05: Some(M05ObjectiveState {
                completed,
                current,
                workshop_secured: self.encounters.is_complete(prepared.rescue_encounter),
                group_released: p.group_released,
                captives: p.captives.clone(),
                freight_open: p.freight_open,
                tram: p.tram.clone(),
                carried_recall_cars: run
                    .solo
                    .as_ref()
                    .map(|s| s.carried_recall_cars.clone())
                    .unwrap_or_default(),
                carried_patients: run
                    .solo
                    .as_ref()
                    .map(|s| s.carried_patients.clone())
                    .unwrap_or_default(),
                carried_photos: run.solo.as_ref().map_or(0, |s| s.carried_photos),
            }),
        })
    }
    pub(crate) fn advance_m05_captives(&mut self, dt: f32) {
        if !dt.is_finite() || dt <= 0.0 || self.campaign_run_frozen() {
            return;
        }
        let Some(run) = self
            .mission
            .as_ref()
            .filter(|r| r.phase == MissionPhase::InProgress)
        else {
            return;
        };
        let Some(prepared) = run.initial_map.m05_objectives() else {
            return;
        };
        let g = prepared.geometry.clone();
        // The rescue follows its ordered predecessors. Every reader rejects
        // released workers before the paint bay's lesson is complete.
        let release = self.encounters.is_complete(prepared.rescue_encounter)
            && run.m05.as_ref().is_some_and(|p| p.index >= 2)
            && self.players.iter().any(|p| {
                p.is_participant()
                    && p.hp > 0
                    && p.respawn_timer.is_none()
                    && run.ready.contains(&p.id)
                    && g.rescue.release.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])
            });
        let arena = self.current_arena().into_owned();
        let mut contacts = self.contact_bodies();
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let Some(p) = run.m05.as_mut() else {
            return;
        };
        if release && !p.group_released {
            p.group_released = true;
            run.changed_at = self.tick;
            tracing::info!("Splice and workshop captives rescued");
        }
        if !p.group_released || dt <= 0.0 {
            return;
        }
        let dt = dt.min(0.05);
        for ((c, index), route) in p
            .captives
            .iter_mut()
            .zip(&mut p.route_points)
            .zip(&p.settling_routes)
        {
            let Some(target) = route.get(*index) else {
                continue;
            };
            let dx = target[0] - c.feet[0];
            let dz = target[2] - c.feet[2];
            let d = dx.hypot(dz);
            // Finish the last small grounded step before changing direction.
            // A broad threshold leaves a route corner just outside boarding.
            if d <= 0.000001 {
                *index += 1;
                continue;
            }
            let speed = 2.0_f32.min(d / dt);
            let body = crate::movement::MoveState {
                x: c.feet[0],
                y: c.feet[1],
                z: c.feet[2],
                vx: dx / d * speed,
                vz: dz / d * speed,
                vy: 0.0,
                yaw: 0.0,
            };
            let proposed = crate::movement::integrate(body, false, dt, &arena);
            let key = format!("m05/{}", c.id);
            let moved = super::contact::move_on_route(
                &key,
                body,
                proposed,
                [dx / d, dz / d],
                dt,
                &arena,
                &contacts,
            );
            if let Some(c) = contacts.iter_mut().find(|c| c.key == key) {
                c.from = moved;
                c.proposed = moved;
            }
            c.feet = [moved.x, moved.y, moved.z];
            run.changed_at = self.tick;
        }
    }
    pub(crate) fn advance_m05_tram(&mut self, dt: f32) {
        if !dt.is_finite() || dt <= 0.0 || self.campaign_run_frozen() {
            return;
        }
        let Some(run) = self
            .mission
            .as_ref()
            .filter(|r| r.phase == MissionPhase::InProgress)
        else {
            return;
        };
        let Some(prepared) = run.initial_map.m05_objectives() else {
            return;
        };
        let g = prepared.geometry.tram.clone();
        let Some(progress) = run.m05.as_ref() else {
            return;
        };
        let old = progress.tram.clone();
        if old.phase == M05TramPhase::Parked {
            if !progress.group_released
                || !self.players.iter().any(|p| {
                    p.is_participant()
                        && p.hp > 0
                        && p.respawn_timer.is_none()
                        && run.ready.contains(&p.id)
                        && g.activation.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])
                })
            {
                return;
            }
            if let Some(run) = &mut self.mission {
                if let Some(p) = &mut run.m05 {
                    p.tram.phase = M05TramPhase::Boarding;
                    p.tram.tick = self.tick;
                    p.boarding_until = self.tick.saturating_add(60);
                    run.changed_at = self.tick;
                }
            }
            tracing::info!("Patched tram boarding");
            return;
        }
        if old.phase == M05TramPhase::Arrived
            || old.phase == M05TramPhase::Boarding && self.tick < progress.boarding_until
        {
            return;
        }
        let dz = (g.end[2] - old.feet[2]).signum()
            * ((g.end[2] - old.feet[2]).abs().min(g.speed * dt.min(0.05)));
        let baseline = self.map.arena().solids[g.solid];
        let old_body = g.body(baseline, old.feet);
        let next_feet = [old.feet[0], old.feet[1], old.feet[2] + dz];
        let new_body = g.body(baseline, next_feet);
        let mut other = self.map.arena().clone();
        other.solids.remove(g.solid);
        let mut riders = Vec::new();
        let mut blocked = false;
        for p in self.players.iter().filter(|p| self.contact_eligible(p)) {
            let b = crate::movement::MoveState {
                x: p.x,
                y: p.y - PLAYER_FLOOR_Y,
                z: p.z,
                vx: 0.0,
                vz: 0.0,
                vy: p.vy,
                yaw: p.yaw,
            };
            if platform::supported(b, old_body, p.platform_jump_requested()) {
                if let Some(moved) = platform::carried(b, dz, &other) {
                    riders.push((p.id, moved.z));
                } else {
                    blocked = true;
                    break;
                }
            } else if p.x + crate::movement::RADIUS > new_body.min_x
                && p.x - crate::movement::RADIUS < new_body.max_x
                && p.z + crate::movement::RADIUS > old_body.min_z.min(new_body.min_z)
                && p.z - crate::movement::RADIUS < old_body.max_z.max(new_body.max_z)
                && b.y + crate::combat::target_height(p.campaign) > new_body.bottom
                && b.y < new_body.top
            {
                blocked = true;
                break;
            }
        }
        if !blocked {
            let mut bodies = self.contact_bodies();
            for body in &mut bodies {
                if let Some((_, z)) = riders.iter().find(|(id, _)| id.to_string() == body.key) {
                    body.proposed.z = *z;
                }
            }
            for (i, a) in bodies.iter().enumerate() {
                for b in &bodies[i + 1..] {
                    if crate::movement::contact::sweep_time(a, b).is_some() {
                        blocked = true;
                    }
                }
            }
        }
        if !blocked {
            for (id, z) in riders {
                if let Some(p) = self.players.iter_mut().find(|p| p.id == id) {
                    p.z = z;
                }
            }
        }
        if let Some(run) = &mut self.mission {
            if let Some(p) = &mut run.m05 {
                p.tram.phase = if blocked {
                    M05TramPhase::Blocked
                } else if (next_feet[2] - g.end[2]).abs() < 0.001 {
                    M05TramPhase::Arrived
                } else {
                    M05TramPhase::Moving
                };
                if !blocked {
                    p.tram.feet = next_feet;
                }
                p.tram.tick = self.tick;
                run.changed_at = self.tick;
            }
        }
    }
    pub(super) fn advance_m05(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        let Some(state) = self.m05_mission_state() else {
            return;
        };
        if state.phase != MissionPhase::InProgress || self.campaign_run_frozen() {
            return;
        }
        let Some(run) = &self.mission else {
            return;
        };
        let Some(prepared) = run.initial_map.m05_objectives() else {
            return;
        };
        let Some(p) = &run.m05 else {
            return;
        };
        if p.index >= 5
            && !p.freight_open
            && self.encounters.is_complete(prepared.departure_encounter)
        {
            if let Some(opened) = self.map.prepared_m05_world() {
                self.map = opened;
            }
            if let Some(run) = &mut self.mission {
                if let Some(p) = &mut run.m05 {
                    p.freight_open = true;
                    run.changed_at = self.tick;
                }
            }
            tracing::info!("Freight platform gate opened");
            return;
        }
        let inside = |region: &crate::protocol::Region3| {
            self.players.iter().any(|p| {
                p.is_participant()
                    && p.hp > 0
                    && p.respawn_timer.is_none()
                    && run.ready.contains(&p.id)
                    && region.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])
            })
        };
        let advance = p.index < 6
            && self.encounters.is_complete(prepared.encounters[p.index])
            && (matches!(&prepared.geometry.objectives[p.index].action,
                MissionObjectiveAction::Arrival { region, .. } if inside(region))
                || super::arrival_passed(&self.encounters, &prepared.encounters, p.index, || {
                    inside(&prepared.geometry.boarding)
                }));
        if advance {
            if let Some(run) = &mut self.mission {
                if let Some(p) = &mut run.m05 {
                    p.index += 1;
                    run.changed_at = self.tick;
                }
            }
            return;
        }
        if !state
            .prompts
            .iter()
            .any(|p| requests.contains(&p.player_id))
        {
            return;
        }
        let exit = if state.run.is_some() {
            let Some(owner) = self
                .mission
                .as_ref()
                .and_then(|r| r.solo.as_ref())
                .and_then(recovery::SoloRun::owner)
            else {
                return;
            };
            let Some(player) = self.players.iter().find(|p| p.id == owner) else {
                return;
            };
            let Ok(entry) = run_file::SavedEntry::from_player(player) else {
                return;
            };
            Some(entry)
        } else {
            None
        };
        if let Some(run) = &mut self.mission {
            run.phase = MissionPhase::Departed;
            run.changed_at = self.tick;
            if let Some(solo) = &mut run.solo {
                if let Some(exit) = exit {
                    solo.capture_exit(exit);
                }
                solo.state.status = crate::protocol::CampaignRunStatus::Complete;
            }
        }
        tracing::info!("Low Water freight departure confirmed");
    }
}
