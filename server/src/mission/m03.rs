//! Scheduled Service facts derive from resolved shots and authored encounters.
use super::*;
use crate::protocol::{
    M03CarState, M03MapGeometry, M03ObjectiveState, MissionObjective, MissionObjectiveAction,
    M03_MAST_MAX_HP,
};

pub(super) struct M03Progress {
    pub(super) mast_hp: i32,
    pub(super) cars: Vec<M03CarState>,
    pub(super) support_shots: u8,
    pub(super) last_support_tick: Option<u64>,
}
impl M03Progress {
    pub(super) fn new(map: M03MapGeometry) -> Self {
        Self {
            mast_hp: M03_MAST_MAX_HP,
            cars: map
                .cars
                .into_iter()
                .map(|car| M03CarState {
                    id: car.id,
                    released: false,
                    captives: car.held,
                })
                .collect(),
            support_shots: 0,
            last_support_tick: None,
        }
    }
}
impl GameState {
    pub(crate) fn ensure_m03_companion(&mut self) {
        if self
            .mission
            .as_ref()
            .is_some_and(|run| run.m03.is_some() && run.phase == MissionPhase::InProgress)
        {
            if let Some(geometry) = self.map.m03_geometry() {
                self.spawn_campaign_companion(geometry.companion_start, false);
            }
        }
    }

    pub(crate) fn m03_liberated_car_ids(&self) -> Vec<String> {
        self.mission
            .as_ref()
            .and_then(|run| run.m03.as_ref())
            .map_or_else(Vec::new, |progress| {
                progress
                    .cars
                    .iter()
                    .filter(|car| car.released)
                    .map(|car| car.id.clone())
                    .collect()
            })
    }

    pub(super) fn m03_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let progress = run.m03.as_ref()?;
        let prepared = run.initial_map.m03_objectives()?;
        let geometry = &prepared.geometry;
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
                        && geometry.boarding.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z]),
                }
            })
            .collect();
        let mast_secured = self.encounters.is_complete(prepared.mast_encounter);
        let train_secured = self.encounters.is_complete(prepared.departure_encounter);
        let departure_ready = run.phase == MissionPhase::InProgress
            && progress.mast_hp == 0
            && train_secured
            && !self.campaign_run_frozen()
            && !party.is_empty()
            && party
                .iter()
                .all(|member| member.ready && member.alive && member.aboard);
        let prompts = if departure_ready {
            self.players
                .iter()
                .filter(|p| p.is_participant() && can_use(p, &geometry.departure, &self.map))
                .map(|p| InteractionPrompt {
                    player_id: p.id,
                    kind: InteractionKind::ObjectiveUse,
                })
                .collect()
        } else {
            Vec::new()
        };
        let current = if run.phase == MissionPhase::Departed {
            None
        } else if progress.mast_hp > 0 {
            Some(MissionObjective {
                id: "mast_disabled".into(),
                action: MissionObjectiveAction::Shoot {
                    solid: geometry.mast.solid,
                    approach: geometry.mast.approach,
                    aim: geometry.mast.aim,
                },
            })
        } else {
            Some(MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: geometry.departure.clone(),
                },
            })
        };
        Some(MissionState {
            id: MissionId::ScheduledService,
            run: run.solo.as_ref().map(|solo| solo.state),
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            m02: None,
            m04: None,
            m05: None,
            m06: None,
            m08: None,
            m07: None,
            m09: None,
            m10: None,
            m11: None,
            m03: Some(M03ObjectiveState {
                mast_hp: progress.mast_hp,
                mast_secured,
                train_secured,
                cars: progress.cars.clone(),
                current,
            }),
        })
    }

    /// Only the normal combat resolver calls this with its internal solid identity.
    pub(crate) fn damage_m03_mast(
        &mut self,
        shooter: Uuid,
        solid: usize,
        end: [f32; 3],
        normal: [f32; 3],
        damage: i32,
    ) {
        let Some(run) = self
            .mission
            .as_ref()
            .filter(|run| run.phase == MissionPhase::InProgress && run.m03.is_some())
        else {
            return;
        };
        let Some(prepared) = run.initial_map.m03_objectives() else {
            return;
        };
        if damage <= 0
            || self.campaign_run_frozen()
            || solid != prepared.geometry.mast.solid
            || !self.encounters.is_complete(prepared.mast_encounter)
            || !self.players.iter().any(|p| {
                p.id == shooter && p.is_participant() && actor_active(Some(run), p.id, p.campaign)
            })
        {
            return;
        }
        let pod = &run.initial_map.arena().solids[solid];
        let min = [pod.min_x, pod.bottom, pod.min_z];
        let max = [pod.max_x, pod.top, pod.max_z];
        if (0..3).any(|i| !end[i].is_finite() || end[i] < min[i] - 0.001 || end[i] > max[i] + 0.001)
            || !(0..3).any(|i| {
                (normal[i].abs() - 1.0).abs() < 0.001
                    && (0..3).filter(|j| *j != i).all(|j| normal[j].abs() < 0.001)
                    && (end[i] - if normal[i] < 0.0 { min[i] } else { max[i] }).abs() < 0.001
            })
        {
            return;
        }
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let Some(progress) = run.m03.as_mut().filter(|progress| progress.mast_hp > 0) else {
            return;
        };
        progress.mast_hp = progress.mast_hp.saturating_sub(damage).max(0);
        run.changed_at = self.tick;
        if progress.mast_hp == 0 {
            if let Some(fallen) = run.initial_map.prepared_m03_world() {
                self.map = fallen;
            }
            tracing::info!("Scheduled Service recall mast disabled");
        }
    }

    pub(crate) fn advance_m03_captives(&mut self, dt: f32) {
        let dt = dt.clamp(0.0, 0.05);
        if dt == 0.0 {
            return;
        }
        if self.campaign_run_frozen() {
            return;
        }
        let Some(run) = self
            .mission
            .as_ref()
            .filter(|run| run.phase == MissionPhase::InProgress)
        else {
            return;
        };
        let Some(prepared) = run.initial_map.m03_objectives() else {
            return;
        };
        let release: Vec<_> = prepared
            .geometry
            .cars
            .iter()
            .zip(&prepared.car_encounters)
            .map(|(car, encounter)| {
                self.encounters.is_complete(*encounter)
                    && self.players.iter().any(|p| {
                        p.is_participant()
                            && p.hp > 0
                            && p.respawn_timer.is_none()
                            && run.ready.contains(&p.id)
                            && car.release.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])
                    })
            })
            .collect();
        let geometry = prepared.geometry.clone();
        let mut contacts = self.contact_bodies();
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let Some(progress) = run.m03.as_mut() else {
            return;
        };
        for ((car, definition), clear) in progress.cars.iter_mut().zip(&geometry.cars).zip(release)
        {
            if clear && !car.released {
                car.released = true;
                run.changed_at = self.tick;
                tracing::info!(car = %car.id, "Recall car liberated");
            }
            if !car.released {
                continue;
            }
            for (i, (feet, target)) in car.captives.iter_mut().zip(definition.safe).enumerate() {
                let dx = target[0] - feet[0];
                let dz = target[2] - feet[2];
                let distance = dx.hypot(dz);
                if distance <= 0.001 {
                    continue;
                }
                let speed = 2.0_f32.min(distance / dt.max(0.001));
                let body = crate::movement::MoveState {
                    x: feet[0],
                    y: feet[1],
                    z: feet[2],
                    vx: dx / distance * speed,
                    vz: dz / distance * speed,
                    vy: 0.0,
                    yaw: 0.0,
                };
                let proposed = crate::movement::integrate(body, false, dt, self.map.arena());
                let key = format!("m03/{}/{i}", car.id);
                let moved = super::contact::move_on_route(
                    &key,
                    body,
                    proposed,
                    [dx / distance, dz / distance],
                    dt,
                    self.map.arena(),
                    &contacts,
                );
                if let Some(c) = contacts.iter_mut().find(|c| c.key == key) {
                    c.from = moved;
                    c.proposed = moved;
                }
                *feet = [moved.x, moved.y, moved.z];
            }
        }
    }

    pub(super) fn advance_m03(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        let Some(state) = self.m03_mission_state() else {
            return;
        };
        if !state
            .prompts
            .iter()
            .any(|prompt| requests.contains(&prompt.player_id))
        {
            return;
        }
        let exit = if state.run.is_some() {
            let Some(owner) = self
                .mission
                .as_ref()
                .and_then(|run| run.solo.as_ref())
                .and_then(recovery::SoloRun::owner)
            else {
                return;
            };
            let Some(player) = self.players.iter().find(|player| player.id == owner) else {
                return;
            };
            let Ok(exit) = run_file::SavedEntry::from_player(player) else {
                return;
            };
            Some(exit)
        } else {
            None
        };
        if let Some(run) = self.mission.as_mut() {
            run.phase = MissionPhase::Departed;
            run.changed_at = self.tick;
            if let Some(solo) = run.solo.as_mut() {
                if let Some(exit) = exit {
                    solo.capture_exit(exit);
                }
                solo.state.status = crate::protocol::CampaignRunStatus::Complete;
            }
            tracing::info!("Scheduled Service train departure confirmed");
        }
    }
}
