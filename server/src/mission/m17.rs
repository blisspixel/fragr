//! Peace Without Interruption: connected Forever Office progression, security core breach and Voss confrontation.
use super::*;
use crate::protocol::{
    InteractionKind, InteractionPrompt, M17ChallengeState, M17ObjectiveState, MissionMember,
    MissionObjectiveAction, MissionPhase, M17_OBJECTIVE_IDS,
};
use crate::sim::PLAYER_FLOOR_Y;
use std::collections::HashSet;

#[derive(Default)]
pub(crate) struct M17Progress {
    pub(super) index: usize,
    pub(super) challenges: M17ChallengeState,
    pub(super) core_unsealed: bool,
    pub(super) voss_captured: bool,
    pub(super) kessel_secured: bool,
}

#[cfg(test)]
mod tests;

impl GameState {
    pub(crate) fn m17_encounter_available(&self, index: usize) -> bool {
        let Some(p) = self.mission.as_ref().and_then(|r| r.m17.as_ref()) else {
            return true;
        };
        match index {
            0 => true,
            1 => p.index >= 1,
            2 => p.index >= 2,
            3 => p.index >= 2,
            4 => p.index >= 3 || p.kessel_secured,
            5 => p.core_unsealed,
            _ => false,
        }
    }

    pub fn m17_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m17.as_ref()?;
        let g = run.initial_map.m17_geometry()?;
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
        let mut completed: Vec<_> = M17_OBJECTIVE_IDS
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
            if !p.kessel_secured && p.index >= 2 && p.index <= 5 {
                prompts.extend(
                    self.players
                        .iter()
                        .filter(|a| {
                            self.contact_eligible(a)
                                && run.ready.contains(&a.id)
                                && can_use_in_arena(a, &g.kessel_desk, &self.map, &arena)
                        })
                        .map(|a| InteractionPrompt {
                            player_id: a.id,
                            kind: InteractionKind::ObjectiveUse,
                        }),
                );
            }
            if !p.core_unsealed && p.index >= 3 {
                prompts.extend(
                    self.players
                        .iter()
                        .filter(|a| {
                            self.contact_eligible(a)
                                && run.ready.contains(&a.id)
                                && can_use_in_arena(a, &g.core_override, &self.map, &arena)
                        })
                        .map(|a| InteractionPrompt {
                            player_id: a.id,
                            kind: InteractionKind::ObjectiveUse,
                        }),
                );
            }
            if !p.voss_captured && p.index == 5 {
                prompts.extend(
                    self.players
                        .iter()
                        .filter(|a| {
                            self.contact_eligible(a)
                                && run.ready.contains(&a.id)
                                && can_use_in_arena(a, &g.voss_rostrum, &self.map, &arena)
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
            id: MissionId::PeaceWithoutInterruption,
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
            m16: None,
            m17: Some(M17ObjectiveState {
                completed,
                current,
                challenges: p.challenges.clone(),
                core_unsealed: p.core_unsealed,
                voss_captured: p.voss_captured,
                kessel_secured: p.kessel_secured,
                brief_completed: p.challenges.brief_completed(run.rules.difficulty),
            }),
            m18: None,
            m19: None,
        })
    }

    pub(super) fn advance_m17(&mut self) {
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
        let Some(g) = self.map.m17_geometry() else {
            return;
        };
        let old = self.m17_mission_state().unwrap().m17.unwrap();
        let index = self.mission.as_ref().unwrap().m17.as_ref().unwrap().index;

        let mut advanced = false;

        // Check optional Kessel custody interaction
        let kessel_secured_already = self
            .mission
            .as_ref()
            .unwrap()
            .m17
            .as_ref()
            .unwrap()
            .kessel_secured;
        if !kessel_secured_already {
            let used_kessel = self.players.iter().any(|pl| {
                requests.contains(&pl.id)
                    && pl.is_participant()
                    && self.contact_eligible(pl)
                    && can_use_in_arena(pl, &g.kessel_desk, &self.map, self.map.arena())
            });
            if used_kessel {
                let p = self.mission.as_mut().unwrap().m17.as_mut().unwrap();
                p.kessel_secured = true;
                p.challenges.kessel_secured = true;
                if p.index == 2 {
                    p.index = 3;
                    advanced = true;
                }
            }
        }

        // Check core override interaction
        let core_unsealed_already = self
            .mission
            .as_ref()
            .unwrap()
            .m17
            .as_ref()
            .unwrap()
            .core_unsealed;
        if !core_unsealed_already && index >= 3 {
            let used_override = self.players.iter().any(|pl| {
                requests.contains(&pl.id)
                    && pl.is_participant()
                    && self.contact_eligible(pl)
                    && can_use_in_arena(pl, &g.core_override, &self.map, self.map.arena())
            });
            if used_override {
                if let Some(world) = self.map.prepared_m17_world(1) {
                    self.map = world;
                    let p = self.mission.as_mut().unwrap().m17.as_mut().unwrap();
                    p.core_unsealed = true;
                    if p.index == 3 {
                        p.index = 4;
                        advanced = true;
                    }
                }
            }
        }

        if index == 0 {
            let arrived_at_hall = match &g.objectives[0].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if arrived_at_hall {
                let p = self.mission.as_mut().unwrap().m17.as_mut().unwrap();
                p.challenges.approach_breached = true;
                p.index = 1;
                advanced = true;
            }
        } else if index == 1 {
            let hall_clear = self.encounters.is_complete(1);
            if hall_clear {
                let p = self.mission.as_mut().unwrap().m17.as_mut().unwrap();
                p.index = if p.kessel_secured { 3 } else { 2 };
                advanced = true;
            }
        } else if index == 2 {
            // Objective 2 is kessel_secured. If kessel was secured above, index is already 3.
            // If player pushed ahead past ring holding:
            let ring_clear = self.encounters.is_complete(2);
            let arrived_at_galleries = match &g.objectives[3].action {
                MissionObjectiveAction::Use { target } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && (a.x - target.approach[0]).hypot(a.z - target.approach[2]) < 5.0
                }),
                _ => false,
            };
            if ring_clear && arrived_at_galleries {
                let p = self.mission.as_mut().unwrap().m17.as_mut().unwrap();
                p.index = 3;
                advanced = true;
            }
        } else if index == 3 {
            // If core was unsealed above, index is already 4.
        } else if index == 4 {
            let core_clear = self.encounters.is_complete(5);
            if core_clear {
                let p = self.mission.as_mut().unwrap().m17.as_mut().unwrap();
                p.challenges.core_defeated = true;
                p.index = 5;
                advanced = true;
            }
        } else if index == 5 {
            let used_voss = self.players.iter().any(|pl| {
                requests.contains(&pl.id)
                    && pl.is_participant()
                    && self.contact_eligible(pl)
                    && can_use_in_arena(pl, &g.voss_rostrum, &self.map, self.map.arena())
            });
            if used_voss {
                let Some(world) = self.map.prepared_m17_world(2) else {
                    return;
                };
                self.map = world;
                let p = self.mission.as_mut().unwrap().m17.as_mut().unwrap();
                p.voss_captured = true;
                p.challenges.voss_captured = true;
                p.index = 6;
                advanced = true;
            }
        }
        let new = self.m17_mission_state().unwrap();
        if new.m17.as_ref().unwrap() != &old {
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
