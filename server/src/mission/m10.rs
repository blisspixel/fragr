//! Common Carrier ordered boarding defense and fresh party confirmation.
use super::*;
use crate::protocol::{M10ObjectiveState, MissionObjective, MissionObjectiveAction};

#[derive(Default)]
pub(super) struct M10Progress {
    pub(super) index: usize,
}

/// Ordered Arrival objectives before the shared departure.
const OBJECTIVES: usize = crate::protocol::M10_OBJECTIVE_IDS.len();

impl GameState {
    pub(crate) fn ensure_m10_companion(&mut self) {
        if self
            .mission
            .as_ref()
            .is_some_and(|r| r.m10.is_some() && r.phase == MissionPhase::InProgress)
        {
            if let Some(g) = self.map.m10_geometry() {
                self.spawn_campaign_companion(g.companion_start, false);
            }
        }
    }

    pub(super) fn m10_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m10.as_ref()?;
        let prepared = run.initial_map.m10_objectives()?;
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
            && self.encounters.is_complete(OBJECTIVES - 1)
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
            m07: None,
            m08: None,
            id: MissionId::CommonCarrier,
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
            m10: Some(M10ObjectiveState {
                completed,
                current,
                transit: solo
                    .and_then(|s| s.carried_transit.clone())
                    .unwrap_or(crate::protocol::M10Transit::HistoricalUnrecorded {}),
                pilot: g.pilot,
                passengers: g
                    .passengers
                    .iter()
                    .filter(|p| {
                        solo.and_then(|s| s.carried_transit.as_ref())
                            .is_some_and(|t| t.arrived(&p.id))
                    })
                    .cloned()
                    .collect(),
                carried_archive: solo.and_then(|s| s.carried_archive.clone()),
            }),
        })
    }

    pub(super) fn advance_m10(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        let Some(state) = self.m10_mission_state() else {
            return;
        };
        if state.phase != MissionPhase::InProgress || self.campaign_run_frozen() {
            return;
        }
        let Some(run) = &self.mission else {
            return;
        };
        let Some(prepared) = run.initial_map.m10_objectives() else {
            return;
        };
        let Some(progress) = &run.m10 else {
            return;
        };
        let arrived = |action: &MissionObjectiveAction| {
            matches!(action, MissionObjectiveAction::Arrival { region, .. }
                if self.players.iter().any(|p| p.is_participant() && p.hp > 0 && p.respawn_timer.is_none()
                    && run.ready.contains(&p.id) && region.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])))
        };
        let advance = progress.index < OBJECTIVES
            && self.encounters.is_complete(progress.index)
            && (arrived(&prepared.geometry.objectives[progress.index].action)
                || super::arrival_passed(&self.encounters, &[0, 1, 2, 3], progress.index, || {
                    self.players.iter().any(|p| {
                        p.is_participant()
                            && p.hp > 0
                            && p.respawn_timer.is_none()
                            && run.ready.contains(&p.id)
                            && prepared
                                .geometry
                                .boarding
                                .contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])
                    })
                }));
        if advance {
            let reached = prepared.geometry.objectives[progress.index].id.clone();
            if let Some(run) = &mut self.mission {
                if let Some(progress) = &mut run.m10 {
                    progress.index += 1;
                    run.changed_at = self.tick;
                }
            }
            tracing::info!(objective = %reached, "Common Carrier objective reached");
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
        tracing::info!("Common Carrier ship secured");
    }
}
