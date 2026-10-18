//! All Systems Normal: Episode V recovery, synchronized rupture, and evacuation concourse progression.
use super::*;
use crate::protocol::{
    InteractionKind, InteractionPrompt, M18ChallengeState, M18ObjectiveState, MissionMember,
    MissionObjectiveAction, MissionPhase, M18_OBJECTIVE_IDS,
};
use crate::sim::PLAYER_FLOOR_Y;
use std::collections::HashSet;

#[derive(Default)]
pub(crate) struct M18Progress {
    pub(super) index: usize,
    pub(super) challenges: M18ChallengeState,
    pub(super) aid_delivered: bool,
    pub(super) square_defended: bool,
    pub(super) collector_neutralized: bool,
    pub(super) overlook_witnessed: bool,
    pub(super) concourse_secured: bool,
    pub(super) roadblock_active: bool,
}

#[cfg(test)]
mod tests;

impl GameState {
    pub(crate) fn m18_encounter_available(&self, index: usize) -> bool {
        let Some(p) = self.mission.as_ref().and_then(|r| r.m18.as_ref()) else {
            return true;
        };
        match index {
            0 => true,
            1 => p.index >= 2,
            2 => p.index >= 3,
            3 => p.index >= 4,
            4 => p.index >= 5,
            _ => false,
        }
    }

    pub fn m18_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m18.as_ref()?;
        let g = run.initial_map.m18_geometry()?;
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
        let mut completed: Vec<_> = M18_OBJECTIVE_IDS
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
            if !p.aid_delivered && p.index == 0 {
                prompts.extend(
                    self.players
                        .iter()
                        .filter(|a| {
                            self.contact_eligible(a)
                                && run.ready.contains(&a.id)
                                && can_use_in_arena(a, &g.depot_station, &self.map, &arena)
                        })
                        .map(|a| InteractionPrompt {
                            player_id: a.id,
                            kind: InteractionKind::ObjectiveUse,
                        }),
                );
            }
            if !p.overlook_witnessed && p.index == 4 {
                prompts.extend(
                    self.players
                        .iter()
                        .filter(|a| {
                            self.contact_eligible(a)
                                && run.ready.contains(&a.id)
                                && can_use_in_arena(a, &g.overlook_console, &self.map, &arena)
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
            id: MissionId::AllSystemsNormal,
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
            m17: None,
            m18: Some(M18ObjectiveState {
                completed,
                current,
                challenges: p.challenges.clone(),
                roadblock_active: p.roadblock_active,
                aid_delivered: p.aid_delivered,
                overlook_witnessed: p.overlook_witnessed,
                concourse_secured: p.concourse_secured,
                brief_completed: p.challenges.brief_completed(run.rules.difficulty),
            }),
        })
    }

    pub(super) fn advance_m18(&mut self) {
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
        let Some(g) = self.map.m18_geometry() else {
            return;
        };
        let old = self.m18_mission_state().unwrap().m18.unwrap();
        let index = self.mission.as_ref().unwrap().m18.as_ref().unwrap().index;

        let mut advanced = false;

        if index == 0 {
            let used_depot = self.players.iter().any(|pl| {
                requests.contains(&pl.id)
                    && pl.is_participant()
                    && self.contact_eligible(pl)
                    && can_use_in_arena(pl, &g.depot_station, &self.map, self.map.arena())
            });
            if used_depot {
                let p = self.mission.as_mut().unwrap().m18.as_mut().unwrap();
                p.aid_delivered = true;
                p.challenges.aid_delivered = true;
                p.index = 1;
                advanced = true;
            }
        } else if index == 1 {
            let square_clear = self.encounters.is_complete(0);
            let arrived = match &g.objectives[1].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if square_clear && arrived {
                let p = self.mission.as_mut().unwrap().m18.as_mut().unwrap();
                p.square_defended = true;
                p.challenges.square_defended = true;
                p.index = 2;
                advanced = true;
            }
        } else if index == 2 {
            let escort_clear = self.encounters.is_complete(1);
            let arrived = match &g.objectives[2].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if escort_clear && arrived {
                let Some(world) = self.map.prepared_m18_world(1) else {
                    return;
                };
                // A party may be standing on the intact low slab. Keep the old
                // world until every living body has cleared the rising rubble.
                let occupied = world
                    .arena()
                    .solids
                    .iter()
                    .zip(&self.map.arena().solids)
                    .filter(|(new, old)| new.top > old.top)
                    .any(|(solid, _)| {
                        self.players.iter().any(|pl| {
                            pl.hp > 0
                                && pl.respawn_timer.is_none()
                                && pl.x + crate::movement::RADIUS > solid.min_x
                                && pl.x - crate::movement::RADIUS < solid.max_x
                                && pl.z + crate::movement::RADIUS > solid.min_z
                                && pl.z - crate::movement::RADIUS < solid.max_z
                                && pl.y - PLAYER_FLOOR_Y < solid.top
                                && pl.y - PLAYER_FLOOR_Y
                                    + crate::combat::body_height(pl.campaign, pl.ducking)
                                    > solid.bottom
                        })
                    });
                if occupied {
                    return;
                }
                self.map = world;
                let p = self.mission.as_mut().unwrap().m18.as_mut().unwrap();
                p.collector_neutralized = true;
                p.challenges.collector_neutralized = true;
                p.roadblock_active = true;
                p.index = 3;
                advanced = true;
            }
        } else if index == 3 {
            let stair_clear = self.encounters.is_complete(2);
            let arrived = match &g.objectives[3].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if stair_clear && arrived {
                let p = self.mission.as_mut().unwrap().m18.as_mut().unwrap();
                p.index = 4;
                advanced = true;
            }
        } else if index == 4 {
            let used_console = self.players.iter().any(|pl| {
                requests.contains(&pl.id)
                    && pl.is_participant()
                    && self.contact_eligible(pl)
                    && can_use_in_arena(pl, &g.overlook_console, &self.map, self.map.arena())
            });
            if used_console {
                let p = self.mission.as_mut().unwrap().m18.as_mut().unwrap();
                p.overlook_witnessed = true;
                p.challenges.overlook_witnessed = true;
                p.index = 5;
                advanced = true;
            }
        } else if index == 5 {
            let concourse_clear = self.encounters.is_complete(4);
            let arrived = match &g.objectives[5].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if concourse_clear && arrived {
                if let Some(world) = self.map.prepared_m18_world(2) {
                    self.map = world;
                }
                let p = self.mission.as_mut().unwrap().m18.as_mut().unwrap();
                p.concourse_secured = true;
                p.challenges.concourse_secured = true;
                p.index = 6;
                advanced = true;
            }
        }

        let new = self.m18_mission_state().unwrap();
        if new.m18.as_ref().unwrap() != &old {
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
