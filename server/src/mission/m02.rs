//! Server-owned M02 progression and objective observations.
use super::*;
use crate::protocol::{M02ObjectiveState, MissionObjective, MissionObjectiveAction};

#[derive(Default)]
pub(super) struct M02Progress {
    pub(super) index: usize,
    pub(super) gate_mask: u8,
}

impl GameState {
    /// The existing mission_ready command enters here only for M02.
    pub fn acknowledge_m02(&mut self, player_id: Uuid, attempt: u32) -> bool {
        let Some(run) = self.mission.as_mut().filter(|run| {
            run.m02.is_some() && run.attempt == attempt && run.phase != MissionPhase::Departed
        }) else {
            return false;
        };
        if !self.players.iter().any(|player| {
            player.id == player_id && player.campaign == Some(CampaignActor::Participant {})
        }) || !run.ready.insert(player_id)
        {
            return false;
        }
        if let Some(player) = self
            .players
            .iter_mut()
            .find(|player| player.id == player_id)
        {
            player.clear_input();
        }
        self.refresh_mission_readiness();
        true
    }

    pub(super) fn m02_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let progress = run.m02.as_ref()?;
        let prepared = run.initial_map.m02_objectives()?;
        let current = prepared.objective(progress.index).and_then(|step| {
            Some(MissionObjective {
                id: step.id.clone(),
                action: if let Some(region) = &step.arrival {
                    MissionObjectiveAction::Arrival {
                        region: region.clone(),
                        feet: step.feet,
                    }
                } else {
                    MissionObjectiveAction::Use {
                        target: step.control.clone()?,
                    }
                },
            })
        });
        let completed = (0..progress.index)
            .filter_map(|index| prepared.objective(index).map(|step| step.id.clone()))
            .collect();
        let exit = prepared
            .objective(prepared.len().checked_sub(1)?)?
            .arrival
            .as_ref()?;
        let party: Vec<_> = self
            .players
            .iter()
            .filter(|player| player.campaign == Some(CampaignActor::Participant {}))
            .map(|player| {
                let ready = run.ready.contains(&player.id);
                let alive = player.hp > 0 && player.respawn_timer.is_none();
                MissionMember {
                    id: player.id,
                    name: player.name.clone(),
                    ready,
                    alive,
                    aboard: run.phase != MissionPhase::Briefing
                        && ready
                        && alive
                        && exit.contains([player.x, player.y - PLAYER_FLOOR_Y, player.z]),
                }
            })
            .collect();
        let prompts = if run.phase == MissionPhase::InProgress {
            current
                .as_ref()
                .and_then(|objective| match &objective.action {
                    MissionObjectiveAction::Use { target } => Some(
                        self.players
                            .iter()
                            .filter(|player| {
                                player.campaign == Some(CampaignActor::Participant {})
                                    && player.hp > 0
                                    && player.respawn_timer.is_none()
                                    && run.ready.contains(&player.id)
                                    && can_use(player, target, &self.map)
                            })
                            .map(|player| InteractionPrompt {
                                player_id: player.id,
                                kind: InteractionKind::ObjectiveUse,
                            })
                            .collect(),
                    ),
                    MissionObjectiveAction::Arrival { .. } => None,
                })
                .unwrap_or_default()
        } else {
            Vec::new()
        };
        Some(MissionState {
            id: MissionId::PersonsUnknown,
            run: None,
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            m02: Some(M02ObjectiveState {
                completed,
                total: u8::try_from(prepared.len()).ok()?,
                gate_mask: progress.gate_mask,
                current,
            }),
        })
    }

    pub(super) fn advance_m02(&mut self) {
        // Failed or early presses are consumed, including during a briefing,
        // after death, and on an arrival objective.
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|player| {
                std::mem::take(&mut player.interaction_requested).then_some(player.id)
            })
            .collect();
        let Some(run) = self.mission.as_ref() else {
            return;
        };
        let Some(progress) = run.m02.as_ref() else {
            return;
        };
        if run.phase == MissionPhase::Briefing
            || run.phase == MissionPhase::Departed
            || self.campaign_run_frozen()
        {
            return;
        }
        let Some(prepared) = run.initial_map.m02_objectives() else {
            return;
        };
        let Some(objective) = prepared.objective(progress.index) else {
            return;
        };
        let active = |player: &Player| {
            player.hp > 0
                && player.respawn_timer.is_none()
                && actor_active(self.mission.as_ref(), player.id, player.campaign)
        };
        let eligible = if objective.id == "party_departed" {
            // Match M01's shared departure: every current participant counts.
            // A dead or unready member blocks the exit, even if another is aboard.
            let mut party = self
                .players
                .iter()
                .filter(|player| player.campaign == Some(CampaignActor::Participant {}));
            party.next().is_some_and(|first| {
                let aboard = |player: &Player| {
                    active(player)
                        && objective.arrival.as_ref().is_some_and(|region| {
                            region.contains([player.x, player.y - PLAYER_FLOOR_Y, player.z])
                        })
                };
                aboard(first) && party.all(aboard)
            })
        } else {
            self.players.iter().any(|player| {
                player.campaign == Some(CampaignActor::Participant {})
                    && active(player)
                    && if let Some(region) = &objective.arrival {
                        region.contains([player.x, player.y - PLAYER_FLOOR_Y, player.z])
                    } else if let Some(control) = &objective.control {
                        requests.contains(&player.id) && can_use(player, control, &self.map)
                    } else {
                        false
                    }
            })
        };
        if !eligible {
            return;
        }
        let next = progress.index + 1;
        let completed = next == prepared.len();
        let completed_id = objective.id.clone();
        let next_mask = prepared
            .objective(next)
            .map_or(objective.required_mask, |step| step.required_mask);
        let next_world = if next_mask != progress.gate_mask {
            run.initial_map.prepared_gate_world(next_mask)
        } else {
            None
        };
        if next_mask != progress.gate_mask && next_world.is_none() {
            return;
        }
        if let Some(world) = next_world {
            self.map = world;
        }
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let Some(progress) = run.m02.as_mut() else {
            return;
        };
        progress.index = next;
        progress.gate_mask = next_mask;
        run.changed_at = self.tick;
        if completed {
            run.phase = MissionPhase::Departed;
        }
        tracing::info!(objective = %completed_id, gate_mask = next_mask, "M02 objective progressed");
    }
}

#[cfg(test)]
mod tests;
