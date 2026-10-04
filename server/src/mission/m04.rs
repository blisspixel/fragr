//! Low Water progression, optional clinic rescue and physical roof departure.
use super::*;
use crate::protocol::{
    M04MapGeometry, M04ObjectiveState, M04PatientState, MissionObjective, MissionObjectiveAction,
};

pub(super) struct M04Progress {
    pub(super) index: usize,
    pub(super) clinic_open: bool,
    pub(super) patients_released: bool,
    pub(super) patients: Vec<M04PatientState>,
    pub(super) route_points: Vec<usize>,
    pub(super) photos_completed: u32,
    pub(super) support_shots: u8,
    pub(super) last_support_tick: Option<u64>,
}
impl M04Progress {
    pub(super) fn new(geometry: M04MapGeometry) -> Self {
        Self {
            index: 0,
            clinic_open: false,
            patients_released: false,
            route_points: vec![1; geometry.patients.len()],
            patients: geometry
                .patients
                .into_iter()
                .map(|p| M04PatientState {
                    id: p.id,
                    feet: p.held,
                })
                .collect(),
            photos_completed: 0,
            support_shots: 0,
            last_support_tick: None,
        }
    }
}
impl GameState {
    pub(crate) fn ensure_m04_companion(&mut self) {
        if self
            .mission
            .as_ref()
            .is_some_and(|run| run.m04.is_some() && run.phase == MissionPhase::InProgress)
        {
            if let Some(g) = self.map.m04_geometry() {
                self.spawn_campaign_companion(g.companion_start, false);
            }
        }
    }
    pub(crate) fn m04_rescued_patient_ids(&self) -> Vec<String> {
        self.mission
            .as_ref()
            .and_then(|r| r.m04.as_ref())
            .filter(|p| p.patients_released)
            .map_or_else(Vec::new, |p| {
                p.patients.iter().map(|p| p.id.clone()).collect()
            })
    }
    pub(crate) fn m04_photos_completed(&self) -> u32 {
        self.mission
            .as_ref()
            .and_then(|r| r.m04.as_ref())
            .map_or(0, |p| p.photos_completed)
    }
    pub(crate) fn note_notary_photograph(&mut self) {
        if let Some(run) = self
            .mission
            .as_mut()
            .filter(|r| r.phase == MissionPhase::InProgress)
        {
            if let Some(p) = run.m04.as_mut() {
                p.photos_completed = p.photos_completed.saturating_add(1).min(1_000_000);
                run.changed_at = self.tick;
            }
        }
    }
    pub(super) fn m04_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m04.as_ref()?;
        let prepared = run.initial_map.m04_objectives()?;
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
        let clinic_secured = self.encounters.is_complete(prepared.clinic_encounter);
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
        let departure_ready = p.index == 6
            && self.encounters.is_complete(prepared.departure_encounter)
            && !party.is_empty()
            && party.iter().all(|m| m.ready && m.alive && m.aboard);
        let prompts = if run.phase == MissionPhase::InProgress && !self.campaign_run_frozen() {
            self.players
                .iter()
                .filter(|p| {
                    p.is_participant()
                        && p.hp > 0
                        && p.respawn_timer.is_none()
                        && run.ready.contains(&p.id)
                })
                .filter_map(|player| {
                    let kind = if clinic_secured
                        && !p.clinic_open
                        && can_use(player, &g.clinic.control, &self.map)
                    {
                        InteractionKind::ClinicShutter
                    } else if departure_ready && can_use(player, &g.departure, &self.map) {
                        InteractionKind::ObjectiveUse
                    } else {
                        return None;
                    };
                    Some(InteractionPrompt {
                        player_id: player.id,
                        kind,
                    })
                })
                .collect()
        } else {
            Vec::new()
        };
        Some(MissionState {
            id: MissionId::NoticeToVacate,
            run: run.solo.as_ref().map(|s| s.state),
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            m02: None,
            m03: None,
            m05: None,
            m06: None,
            m08: None,
            m07: None,
            m09: None,
            m04: Some(M04ObjectiveState {
                completed,
                current,
                clinic_secured,
                clinic_open: p.clinic_open,
                patients_released: p.patients_released,
                patients: p.patients.clone(),
                photos_completed: p.photos_completed,
                carried_recall_cars: run
                    .solo
                    .as_ref()
                    .map(|s| s.carried_recall_cars.clone())
                    .unwrap_or_default(),
            }),
        })
    }
    pub(crate) fn advance_m04_patients(&mut self, dt: f32) {
        if self.campaign_run_frozen() {
            return;
        }
        let Some(run) = self
            .mission
            .as_ref()
            .filter(|r| r.phase == MissionPhase::InProgress)
        else {
            return;
        };
        let Some(prepared) = run.initial_map.m04_objectives() else {
            return;
        };
        let g = prepared.geometry.clone();
        let mut contacts = self.contact_bodies();
        let approached = self.players.iter().any(|p| {
            p.is_participant()
                && p.hp > 0
                && p.respawn_timer.is_none()
                && run.ready.contains(&p.id)
                && g.clinic.release.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])
        });
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let Some(progress) = run.m04.as_mut() else {
            return;
        };
        if progress.clinic_open && approached && !progress.patients_released {
            progress.patients_released = true;
            run.changed_at = self.tick;
            tracing::info!("Low Water clinic team rescued");
        }
        if !progress.patients_released || dt <= 0.0 {
            return;
        }
        let dt = dt.min(0.05);
        for ((patient, index), route) in progress
            .patients
            .iter_mut()
            .zip(&mut progress.route_points)
            .zip(&g.patients)
        {
            let Some(target) = route.route.get(*index) else {
                continue;
            };
            let dx = target[0] - patient.feet[0];
            let dz = target[2] - patient.feet[2];
            let distance = dx.hypot(dz);
            if distance <= 0.001 {
                *index += 1;
                continue;
            }
            let speed = 2.0_f32.min(distance / dt);
            let body = crate::movement::MoveState {
                x: patient.feet[0],
                y: patient.feet[1],
                z: patient.feet[2],
                vx: dx / distance * speed,
                vz: dz / distance * speed,
                vy: 0.0,
                yaw: 0.0,
            };
            let proposed = crate::movement::integrate(body, false, dt, self.map.arena());
            let key = format!("m04/{}", patient.id);
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
            patient.feet = [moved.x, moved.y, moved.z];
        }
    }
    pub(super) fn advance_m04(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        let Some(state) = self.m04_mission_state() else {
            return;
        };
        if state.phase != MissionPhase::InProgress || self.campaign_run_frozen() {
            return;
        }
        if state
            .prompts
            .iter()
            .any(|p| p.kind == InteractionKind::ClinicShutter && requests.contains(&p.player_id))
        {
            if let Some(opened) = self.map.prepared_m04_world() {
                self.map = opened;
            }
            if let Some(run) = self.mission.as_mut() {
                if let Some(p) = run.m04.as_mut() {
                    p.clinic_open = true;
                    run.changed_at = self.tick;
                }
            }
            tracing::info!("Low Water clinic shutter opened");
        }
        let Some(run) = self.mission.as_ref() else {
            return;
        };
        let Some(prepared) = run.initial_map.m04_objectives() else {
            return;
        };
        let Some(p) = run.m04.as_ref() else {
            return;
        };
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
            if let Some(run) = self.mission.as_mut() {
                if let Some(p) = run.m04.as_mut() {
                    p.index += 1;
                    run.changed_at = self.tick;
                }
            }
            return;
        }
        if !state
            .prompts
            .iter()
            .any(|p| p.kind == InteractionKind::ObjectiveUse && requests.contains(&p.player_id))
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
        if let Some(run) = self.mission.as_mut() {
            run.phase = MissionPhase::Departed;
            run.changed_at = self.tick;
            if let Some(solo) = run.solo.as_mut() {
                if let Some(exit) = exit {
                    solo.capture_exit(exit);
                }
                solo.state.status = crate::protocol::CampaignRunStatus::Complete;
            }
        }
        tracing::info!("Low Water roof departure confirmed");
    }
}
