//! Server-owned M02 progression and objective observations.
use super::*;
use crate::protocol::{M02ObjectiveState, MissionObjective, MissionObjectiveAction};

/// Matches the end of the fixed ward tableau. The moving pawn starts here
/// while that tableau is still visible and only moves after its final beat.
pub(crate) const LATCH_SECOND_FEET: [f32; 3] = [7.55, 0.0, -14.8];
pub(crate) const LATCH_RELEASE_TICKS: u64 = 240;

#[derive(Default)]
pub(super) struct M02Progress {
    pub(super) index: usize,
    pub(super) gate_mask: u8,
    pub(super) support_shots: u8,
    pub(super) last_support_tick: Option<u64>,
    evacuation: evacuation::Controller,
}

mod companion;
mod evacuation;
pub(crate) use evacuation::validate_route as validate_m02_evacuation_route;

impl M02Progress {
    pub(super) fn contact_feet(&self) -> [[f32; 3]; 2] {
        self.evacuation.contact_feet()
    }
}

impl GameState {
    fn m02_encounter_complete(&self, id: &str) -> bool {
        self.mission
            .as_ref()
            .filter(|run| run.m02.is_some())
            .and_then(|run| {
                run.initial_map
                    .encounters()
                    .iter()
                    .position(|encounter| encounter.id == id)
            })
            .is_some_and(|index| self.encounters.is_complete(index))
    }

    /// The machine is quiet only after the authored ward group is fully cleared.
    /// This is derived from encounter state, never a second mutable mission flag.
    pub(crate) fn m02_ward_secured(&self) -> bool {
        self.m02_encounter_complete("ward_guards")
    }

    /// The optional group is independent of departure and resets with the
    /// authored encounter state on Continue.
    pub(crate) fn m02_side_ward_secured(&self) -> bool {
        self.m02_encounter_complete("side_ward_guards")
    }

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
            if let Some(solo) = run.solo.as_mut() {
                solo.capture_entry(player, *self.scores.get(&player_id).unwrap_or(&0));
            }
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
                .filter(|_| {
                    prepared.objective(progress.index).is_some_and(|step| {
                        step.required_encounter
                            .is_none_or(|index| self.encounters.is_complete(index))
                    })
                })
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
                    MissionObjectiveAction::Arrival { .. }
                    | MissionObjectiveAction::Shoot { .. } => None,
                })
                .unwrap_or_default()
        } else {
            Vec::new()
        };
        Some(MissionState {
            id: MissionId::PersonsUnknown,
            run: run.solo.as_ref().map(|solo| solo.state),
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            m03: None,
            m04: None,
            m05: None,
            m06: None,
            m08: None,
            m07: None,
            m09: None,
            m02: Some(M02ObjectiveState {
                completed,
                total: u8::try_from(prepared.len()).ok()?,
                gate_mask: progress.gate_mask,
                ward_secured: self.m02_ward_secured(),
                side_ward_secured: self.m02_side_ward_secured(),
                evacuation: run
                    .initial_map
                    .has_m02_side_ward()
                    .then(|| progress.evacuation.published.clone()),
                current,
            }),
        })
    }

    pub(crate) fn advance_m02_evacuation(&mut self, dt: f32) {
        let side_clear = self.m02_side_ward_secured();
        let floor_clear = self.m02_encounter_complete("floor_crew");
        let dock_clear = self.m02_encounter_complete("dock_watch");
        let frozen = self.campaign_run_frozen();
        let contacts = self.contact_bodies();
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        if run.phase != MissionPhase::InProgress || frozen {
            return;
        }
        let Some(progress) = run.m02.as_mut() else {
            return;
        };
        progress.evacuation.set_contacts(contacts);
        progress.evacuation.tick(
            self.tick,
            dt,
            self.map.arena(),
            side_clear,
            floor_clear,
            dock_clear,
        );
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
        if objective
            .required_encounter
            .is_some_and(|index| !self.encounters.is_complete(index))
        {
            return;
        }
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
        let exit = if completed && run.solo.is_some() {
            let Some(owner) = run.solo.as_ref().and_then(recovery::SoloRun::owner) else {
                return;
            };
            let Some(player) = self.players.iter().find(|player| player.id == owner) else {
                return;
            };
            match run_file::SavedEntry::from_player(player) {
                Ok(exit) => Some(exit),
                Err(reason) => {
                    tracing::error!(reason, "M02 exit equipment could not be saved");
                    return;
                }
            }
        } else {
            None
        };
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
            if let Some(solo) = run.solo.as_mut() {
                if let Some(exit) = exit {
                    solo.capture_exit(exit);
                }
                solo.state.status = crate::protocol::CampaignRunStatus::Complete;
            }
        }
        if completed_id == "companion_released" {
            self.spawn_m02_companion();
        }
        tracing::info!(objective = %completed_id, gate_mask = next_mask, "M02 objective progressed");
    }
}

#[cfg(test)]
mod route_tests;
#[cfg(test)]
mod tests;
