//! Server-owned M02 progression. No M02 wire command is exposed in this slice.
use super::*;

#[derive(Default)]
pub(super) struct M02Progress {
    pub(super) index: usize,
    pub(super) gate_mask: u8,
}

impl GameState {
    /// Internal readiness seam for the later M02 protocol. It cannot be called
    /// through the current M01-only network command.
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
