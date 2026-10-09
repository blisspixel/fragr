//! Right of Search ordered tender facts and optional resolved brief receipts.
use super::*;
use crate::protocol::{
    M11ChallengeState, M11ObjectiveState, MissionObjective, MissionObjectiveAction,
};

#[derive(Default)]
pub(super) struct M11Progress {
    pub(super) index: usize,
    pub(super) challenges: M11ChallengeState,
    pub(super) last_remote_blast: u32,
}

const OBJECTIVES: usize = crate::protocol::M11_OBJECTIVE_IDS.len();

#[cfg(test)]
mod tests;

impl GameState {
    pub(crate) fn ensure_m11_companion(&mut self) {
        if self
            .mission
            .as_ref()
            .is_some_and(|r| r.m11.is_some() && r.phase == MissionPhase::InProgress)
        {
            if let Some(g) = self.map.m11_geometry() {
                self.spawn_campaign_companion(g.companion_start, false);
            }
        }
    }

    fn capture_m11_counter_boarding(&mut self) {
        if !self.encounters.is_awake(3) {
            return;
        }
        let Some(run) = self
            .mission
            .as_mut()
            .filter(|r| r.phase == MissionPhase::InProgress)
        else {
            return;
        };
        let Some(p) = run.m11.as_mut() else {
            return;
        };
        if p.challenges.counter_boarding_started.is_some() {
            return;
        }
        let Some(due) = self.tick.checked_add(crate::protocol::M11_SIGNAL_TICKS) else {
            return;
        };
        p.challenges.counter_boarding_started = Some(self.tick);
        p.challenges.signal_due = Some(due);
        run.changed_at = self.tick;
    }

    /// Called only after one actual Remote Mine blast has resolved damage.
    /// Ordinary guns, grenades and proximity mines never enter this writer.
    pub(crate) fn note_m11_remote_blast(&mut self, serial: u32, kills: &[Uuid]) {
        self.capture_m11_counter_boarding();
        let count = kills
            .iter()
            .copied()
            .collect::<HashSet<_>>()
            .into_iter()
            .filter(|id| self.encounters.registered_in_group(*id, 3))
            .count();
        let Some(run) = self
            .mission
            .as_mut()
            .filter(|r| r.phase == MissionPhase::InProgress)
        else {
            return;
        };
        let Some(p) = run.m11.as_mut() else {
            return;
        };
        if p.challenges.counter_boarding_started.is_none() || serial <= p.last_remote_blast {
            return;
        }
        p.last_remote_blast = serial;
        let actual = u8::try_from(count).unwrap_or(6).min(6);
        if actual > p.challenges.counter_boarder_blast_kills {
            p.challenges.counter_boarder_blast_kills = actual;
            run.changed_at = self.tick;
        }
    }

    pub(super) fn m11_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m11.as_ref()?;
        let g = &run.initial_map.m11_objectives()?.geometry;
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
            .map(|o| o.id.clone())
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
            && self.encounters.is_complete(3)
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
                .filter(|actor| {
                    departure_ready && can_use(actor, &g.departure, &self.map)
                        || p.index >= 3
                            && !p.challenges.transfer_released
                            && can_use(actor, &g.transfer_release, &self.map)
                        || p.index >= 4
                            && !p.challenges.records_read
                            && can_use(actor, &g.records_document, &self.map)
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
            id: MissionId::RightOfSearch,
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
            m05: None,
            m06: None,
            m07: None,
            m08: None,
            m09: None,
            m10: None,
            m11: Some(M11ObjectiveState {
                completed,
                current,
                challenges: p.challenges.clone(),
            }),
            m12: None,
        })
    }

    pub(super) fn advance_m11(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
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
        let Some(prepared) = run.initial_map.m11_objectives() else {
            return;
        };
        let Some(progress) = run.m11.as_ref() else {
            return;
        };
        let g = &prepared.geometry;
        let arrived = |action: &MissionObjectiveAction| {
            matches!(action, MissionObjectiveAction::Arrival { region, .. }
                if self.players.iter().any(|p| p.is_participant() && p.hp > 0
                    && p.respawn_timer.is_none() && run.ready.contains(&p.id)
                    && region.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])))
        };
        let index = progress.index;
        let group_clear = match index {
            0 => true,
            1 => self.encounters.is_complete(0),
            2 => self.encounters.is_complete(1),
            3 => self.encounters.is_complete(2),
            4 | 5 => self.encounters.is_complete(3),
            _ => false,
        };
        let passed = match index {
            0 => self.encounters.is_awake(0),
            1..=3 => self.encounters.is_awake(index),
            4 => arrived(&g.objectives[5].action),
            _ => false,
        };
        if index < OBJECTIVES && group_clear && (arrived(&g.objectives[index].action) || passed) {
            if let Some(run) = self.mission.as_mut() {
                if let Some(p) = run.m11.as_mut() {
                    p.index += 1;
                    if p.index == OBJECTIVES {
                        p.challenges.bridge_taken_at = Some(self.tick);
                    }
                    run.changed_at = self.tick;
                }
            }
            self.capture_m11_counter_boarding();
            return;
        }
        let transfer = index >= 3
            && !progress.challenges.transfer_released
            && self.players.iter().any(|p| {
                requests.contains(&p.id)
                    && p.hp > 0
                    && p.is_participant()
                    && run.ready.contains(&p.id)
                    && can_use(p, &g.transfer_release, &self.map)
            });
        let document = index >= 4
            && !progress.challenges.records_read
            && self.players.iter().any(|p| {
                requests.contains(&p.id)
                    && p.hp > 0
                    && p.is_participant()
                    && run.ready.contains(&p.id)
                    && can_use(p, &g.records_document, &self.map)
            });
        if transfer || document {
            if let Some(run) = self.mission.as_mut() {
                if let Some(p) = run.m11.as_mut() {
                    p.challenges.transfer_released |= transfer;
                    p.challenges.records_read |= document;
                    run.changed_at = self.tick;
                }
            }
            self.capture_m11_counter_boarding();
            return;
        }
        self.capture_m11_counter_boarding();
        let Some(state) = self.m11_mission_state() else {
            return;
        };
        if index != OBJECTIVES
            || !self.encounters.is_complete(3)
            || state.party.is_empty()
            || !state.party.iter().all(|m| m.ready && m.alive && m.aboard)
        {
            return;
        }
        let Some(g) = self.map.m11_geometry() else {
            return;
        };
        if !self.players.iter().any(|p| {
            requests.contains(&p.id)
                && p.is_participant()
                && p.hp > 0
                && can_use(p, &g.departure, &self.map)
        }) {
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
    }
}
