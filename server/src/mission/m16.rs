//! Freedom of Movement: connected ceremonial avenue progression, motorcycle traversal and departure.
use super::*;
use crate::protocol::{
    InteractionKind, InteractionPrompt, M16ChallengeState, M16ObjectiveState, MissionMember,
    MissionObjectiveAction, MissionPhase, M16_OBJECTIVE_IDS,
};
use crate::sim::PLAYER_FLOOR_Y;
use std::collections::HashSet;

#[derive(Default)]
pub(crate) struct M16Progress {
    pub(super) index: usize,
    pub(super) challenges: M16ChallengeState,
    pub(super) checkpoint_lifted: bool,
    pub(super) doors_open: bool,
    pub(super) bus_freed: bool,
    pub(super) forecourt_secured: bool,
}

#[cfg(test)]
mod tests;

impl GameState {
    pub(crate) fn m16_encounter_available(&self, index: usize) -> bool {
        let Some(p) = self.mission.as_ref().and_then(|r| r.m16.as_ref()) else {
            return true;
        };
        match index {
            0 => true,
            1 => p.index >= 1,
            2 => p.index >= 2,
            3 => p.index >= 2,
            4 => p.checkpoint_lifted,
            _ => false,
        }
    }

    pub fn m16_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m16.as_ref()?;
        let g = run.initial_map.m16_geometry()?;
        let party: Vec<_> = self
            .players
            .iter()
            .filter(|pl| pl.is_participant())
            .map(|a| {
                let ready = run.ready.contains(&a.id);
                let alive = self.contact_eligible(a);
                MissionMember {
                    id: a.id,
                    name: a.name.clone(),
                    ready,
                    alive: a.hp > 0 && a.respawn_timer.is_none(),
                    aboard: ready && alive && g.boarding.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z]),
                }
            })
            .collect();
        let departed = run.phase == MissionPhase::Departed;
        let mut completed: Vec<_> = M16_OBJECTIVE_IDS
            .iter()
            .take(p.index)
            .map(|id| (*id).to_owned())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = if departed {
            None
        } else if p.index < 6 {
            Some(g.objectives[p.index].clone())
        } else {
            Some(g.departure_objective())
        };
        let arena = self.current_arena();
        let mut prompts = Vec::new();
        if run.phase == MissionPhase::InProgress && !self.campaign_run_frozen() {
            if !p.bus_freed && p.index >= 2 && p.index <= 5 {
                prompts.extend(
                    self.players
                        .iter()
                        .filter(|a| {
                            self.contact_eligible(a)
                                && run.ready.contains(&a.id)
                                && can_use_in_arena(a, &g.bus_release, &self.map, &arena)
                        })
                        .map(|a| InteractionPrompt {
                            player_id: a.id,
                            kind: InteractionKind::ObjectiveUse,
                        }),
                );
            }
            if p.index == 6 {
                let departure_ready =
                    !party.is_empty() && party.iter().all(|m| m.ready && m.alive && m.aboard);
                if departure_ready {
                    prompts.extend(
                        self.players
                            .iter()
                            .filter(|a| {
                                self.contact_eligible(a)
                                    && run.ready.contains(&a.id)
                                    && can_use_in_arena(a, &g.departure, &self.map, &arena)
                            })
                            .map(|a| InteractionPrompt {
                                player_id: a.id,
                                kind: InteractionKind::ObjectiveUse,
                            }),
                    );
                }
            }
        }
        Some(MissionState {
            m20: None,
            id: MissionId::FreedomOfMovement,
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
            m11: None,
            m12: None,
            m13: None,
            m14: None,
            m15: None,
            m16: Some(M16ObjectiveState {
                completed,
                current,
                challenges: p.challenges.clone(),
                checkpoint_lifted: p.checkpoint_lifted,
                doors_open: p.doors_open,
                bus_freed: p.bus_freed,
                forecourt_secured: p.forecourt_secured,
            }),
            m17: None,
            m18: None,
            m19: None,
        })
    }

    pub(super) fn advance_m16(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        if self.campaign_run_frozen()
            || !self
                .mission
                .as_ref()
                .is_some_and(|r| r.phase == MissionPhase::InProgress)
        {
            return;
        }
        let Some(g) = self.map.m16_geometry() else {
            return;
        };
        let old = self.m16_mission_state().unwrap().m16.unwrap();
        let index = self.mission.as_ref().unwrap().m16.as_ref().unwrap().index;

        let mut advanced = false;

        // Check optional or required bus release interaction anytime it is reachable
        let bus_freed_already = self
            .mission
            .as_ref()
            .unwrap()
            .m16
            .as_ref()
            .unwrap()
            .bus_freed;
        if !bus_freed_already {
            let used_bus = self.players.iter().any(|pl| {
                requests.contains(&pl.id)
                    && pl.is_participant()
                    && self.contact_eligible(pl)
                    && can_use_in_arena(pl, &g.bus_release, &self.map, self.map.arena())
            });
            if used_bus {
                let p = self.mission.as_mut().unwrap().m16.as_mut().unwrap();
                p.bus_freed = true;
                p.challenges.bus_freed = true;
                if p.index == 3 {
                    p.index = 4;
                    advanced = true;
                }
            }
        }

        if index == 0 {
            let started_ride = match &g.objectives[0].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if started_ride {
                let p = self.mission.as_mut().unwrap().m16.as_mut().unwrap();
                p.challenges.ride_started = true;
                p.index = 1;
                advanced = true;
            }
        } else if index == 1 {
            let first_stretch_clear = self.encounters.is_complete(0);
            let arrived_at_barricade = match &g.objectives[1].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if first_stretch_clear && arrived_at_barricade {
                let p = self.mission.as_mut().unwrap().m16.as_mut().unwrap();
                p.index = 2;
                advanced = true;
            }
        } else if index == 2 {
            let barricade_post_clear = self.encounters.is_complete(1);
            let arrived_at_checkpoint = match &g.objectives[2].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if barricade_post_clear && arrived_at_checkpoint {
                if let Some(world) = self.map.prepared_m16_world(1) {
                    self.map = world;
                    let p = self.mission.as_mut().unwrap().m16.as_mut().unwrap();
                    p.challenges.green_wave_triggered = true;
                    p.checkpoint_lifted = true;
                    p.index = if p.bus_freed { 4 } else { 3 };
                    advanced = true;
                }
            }
        } else if index == 3 {
            // Objective 3 is bus_freed. If bus was freed above, index is already 4.
            // If player pushed ahead to forecourt without freeing bus:
            let arrived_at_forecourt = match &g.objectives[4].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if arrived_at_forecourt {
                let p = self.mission.as_mut().unwrap().m16.as_mut().unwrap();
                p.index = 4;
                advanced = true;
            }
        } else if index == 4 {
            let forecourt_assault_clear = self.encounters.is_complete(4);
            let arrived_at_forecourt = match &g.objectives[4].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if forecourt_assault_clear && arrived_at_forecourt {
                let p = self.mission.as_mut().unwrap().m16.as_mut().unwrap();
                p.forecourt_secured = true;
                p.index = 5;
                advanced = true;
            }
        } else if index == 5 {
            let arrived_at_doors = match &g.objectives[5].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if arrived_at_doors {
                if let Some(world) = self.map.prepared_m16_world(2) {
                    self.map = world;
                    let p = self.mission.as_mut().unwrap().m16.as_mut().unwrap();
                    p.doors_open = true;
                    p.index = 6;
                    advanced = true;
                }
            }
        }

        let new = self.m16_mission_state().unwrap();
        if advanced || new.m16.as_ref() != Some(&old) {
            self.mission.as_mut().unwrap().changed_at = self.tick;
        }

        if advanced || index < 6 {
            return;
        }

        // Final departure check
        if !new.prompts.iter().any(|p| requests.contains(&p.player_id)) {
            return;
        }
        let exit = if new.run.is_some() {
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
        let run = self.mission.as_mut().unwrap();
        run.phase = MissionPhase::Departed;
        run.changed_at = self.tick;
        if let Some(solo) = &mut run.solo {
            if let Some(exit) = exit {
                solo.capture_exit(exit);
            }
            solo.state.status = crate::protocol::CampaignRunStatus::Complete;
        }
    }
}
