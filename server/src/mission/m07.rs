//! Curfew town progression, the window lesson and the depot freight exit.
use super::*;
use crate::protocol::{M07ObjectiveState, MissionObjective, MissionObjectiveAction};

#[derive(Default)]
pub(super) struct M07Progress {
    pub(super) index: usize,
    pub(super) support_shots: u8,
    pub(super) last_support_tick: Option<u64>,
}

/// Ordered Arrival objectives before the shared departure.
const OBJECTIVES: usize = crate::protocol::M07_OBJECTIVE_IDS.len();

impl GameState {
    pub(crate) fn ensure_m07_companion(&mut self) {
        if self
            .mission
            .as_ref()
            .is_some_and(|r| r.m07.is_some() && r.phase == MissionPhase::InProgress)
        {
            if let Some(g) = self.map.m07_geometry() {
                self.spawn_campaign_companion(g.companion_start, false);
            }
        }
    }

    pub(super) fn m07_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m07.as_ref()?;
        let prepared = run.initial_map.m07_objectives()?;
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
        let mut completed: Vec<_> = g
            .objectives
            .iter()
            .take(p.index.min(OBJECTIVES))
            .map(|s| s.id.clone())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = if departed {
            None
        } else if p.index < OBJECTIVES {
            Some(g.objectives[p.index].clone())
        } else {
            Some(MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: g.departure.clone(),
                },
            })
        };
        let departure_ready = p.index == OBJECTIVES
            && self.encounters.is_complete(prepared.departure_encounter)
            && !party.is_empty()
            && party.iter().all(|m| m.ready && m.alive && m.aboard);
        let prompts = if departure_ready
            && run.phase == MissionPhase::InProgress
            && !self.campaign_run_frozen()
        {
            self.players
                .iter()
                .filter(|p| {
                    p.is_participant()
                        && p.hp > 0
                        && p.respawn_timer.is_none()
                        && run.ready.contains(&p.id)
                        && can_use(p, &g.departure, &self.map)
                })
                .map(|p| InteractionPrompt {
                    player_id: p.id,
                    kind: InteractionKind::ObjectiveUse,
                })
                .collect()
        } else {
            Vec::new()
        };
        let solo = run.solo.as_ref();
        Some(MissionState {
            m08: None,
            id: MissionId::DeclaredGoods,
            run: solo.map(|s| s.state),
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            m02: None,
            m03: None,
            m04: None,
            m05: None,
            m06: None,
            m09: None,
            m10: None,
            m11: None,
            m12: None,
            m07: Some(M07ObjectiveState {
                completed,
                current,
                carried_recall_cars: solo
                    .map(|s| s.carried_recall_cars.clone())
                    .unwrap_or_default(),
                carried_patients: solo.map(|s| s.carried_patients.clone()).unwrap_or_default(),
                carried_photos: solo.map_or(0, |s| s.carried_photos),
                carried_released_workers: solo
                    .map(|s| s.carried_released_workers.clone())
                    .unwrap_or_default(),
                carried_evacuated_workers: solo
                    .map(|s| s.carried_evacuated_workers.clone())
                    .unwrap_or_default(),
                carried_prisoner_route_marked: solo
                    .is_some_and(|s| s.carried_prisoner_route_marked),
            }),
        })
    }

    pub(super) fn advance_m07(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        let Some(state) = self.m07_mission_state() else {
            return;
        };
        if state.phase != MissionPhase::InProgress || self.campaign_run_frozen() {
            return;
        }
        let Some(run) = &self.mission else {
            return;
        };
        let Some(prepared) = run.initial_map.m07_objectives() else {
            return;
        };
        let Some(progress) = &run.m07 else {
            return;
        };
        let arrived = |action: &MissionObjectiveAction| {
            matches!(action, MissionObjectiveAction::Arrival { region, .. }
                if self.players.iter().any(|p| p.is_participant() && p.hp > 0 && p.respawn_timer.is_none()
                    && run.ready.contains(&p.id) && region.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])))
        };
        let advance = progress.index < OBJECTIVES
            && self
                .encounters
                .is_complete(prepared.encounters[progress.index])
            && (arrived(&prepared.geometry.objectives[progress.index].action)
                || super::arrival_passed(
                    &self.encounters,
                    &prepared.encounters,
                    progress.index,
                    || {
                        self.players.iter().any(|p| {
                            p.is_participant()
                                && p.hp > 0
                                && p.respawn_timer.is_none()
                                && run.ready.contains(&p.id)
                                && prepared.geometry.boarding.contains([
                                    p.x,
                                    p.y - PLAYER_FLOOR_Y,
                                    p.z,
                                ])
                        })
                    },
                ));
        if advance {
            let reached = prepared.geometry.objectives[progress.index].id.clone();
            if let Some(run) = &mut self.mission {
                if let Some(progress) = &mut run.m07 {
                    progress.index += 1;
                    run.changed_at = self.tick;
                }
            }
            tracing::info!(objective = %reached, "Declared Goods objective reached");
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
        tracing::info!("Depot freight departure confirmed");
    }
}
