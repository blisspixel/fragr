//! Launch Authority owns staging and the world handoff; ordinary combat owns every hit.
use super::*;
use crate::protocol::{
    M14ChallengeState, M14ObjectiveState, MissionObjectiveAction, WalkerPhase, M14_OBJECTIVE_IDS,
};

#[derive(Default)]
pub(super) struct M14Progress {
    pub(super) index: usize,
    pub(super) challenges: M14ChallengeState,
    pub(super) support_stage: u8,
    pub(super) first_cycle_complete: bool,
    first_recovery_until: Option<u64>,
    pub(super) machine_fallen: bool,
}
#[cfg(test)]
mod tests;
impl GameState {
    pub(crate) fn m14_encounter_available(&self, index: usize) -> bool {
        let Some(p) = self.mission.as_ref().and_then(|r| r.m14.as_ref()) else {
            return true;
        };
        match index {
            0 => p.index >= 1,
            1 => p.index >= 2,
            2 => p.index >= 3,
            3 => p.support_stage >= 1,
            4 => p.support_stage >= 2,
            5 => p.index >= 5,
            _ => false,
        }
    }
    pub(crate) fn m14_walker_active(&self) -> bool {
        self.mission
            .as_ref()
            .and_then(|r| r.m14.as_ref())
            .is_none_or(|p| p.index >= 4 && !p.machine_fallen)
    }
    pub(super) fn m14_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m14.as_ref()?;
        let g = run.initial_map.m14_geometry()?;
        let party: Vec<_> = self
            .players
            .iter()
            .filter(|p| p.is_participant())
            .map(|a| {
                let ready = run.ready.contains(&a.id);
                let alive = self.contact_eligible(a);
                MissionMember {
                    id: a.id,
                    name: a.name.clone(),
                    ready,
                    alive: a.hp > 0 && a.respawn_timer.is_none(),
                    aboard: ready
                        && alive
                        && self.vehicle_seat(a.id).is_none()
                        && g.boarding.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z]),
                }
            })
            .collect();
        let departed = run.phase == MissionPhase::Departed;
        let mut completed: Vec<_> = M14_OBJECTIVE_IDS
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
        let ready = p.index == 6
            && !party.is_empty()
            && party.iter().all(|m| m.ready && m.alive && m.aboard);
        let arena = self.current_arena();
        let prompts =
            if ready && run.phase == MissionPhase::InProgress && !self.campaign_run_frozen() {
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
                    })
                    .collect()
            } else {
                Vec::new()
            };
        Some(MissionState {
            m20: None,
            epilogue: None,
            id: MissionId::LaunchAuthority,
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
            m15: None,
            m16: None,
            m17: None,
            m18: None,
            m19: None,
            m14: Some(M14ObjectiveState {
                completed,
                current,
                challenges: p.challenges.clone(),
                jeep_id: 1,
                support_stage: p.support_stage,
                first_cycle_complete: p.first_cycle_complete,
                machine_fallen: p.machine_fallen,
            }),
        })
    }
    fn try_m14_fall(&mut self) {
        let Some(w) = self
            .walker
            .as_ref()
            .filter(|w| w.state.hp == 0 && w.state.shells.is_empty())
        else {
            return;
        };
        let Some(world) = self.map.prepared_m14_world(w.state.feet) else {
            return;
        };
        let Some(g) = world.m14_geometry() else {
            return;
        };
        for index in g.walker_solids {
            let solid = world.arena().solids[index];
            if self.players.iter().any(|p| {
                self.contact_eligible(p)
                    && self.vehicle_seat(p.id).is_none()
                    && p.x + crate::movement::RADIUS > solid.min_x
                    && p.x - crate::movement::RADIUS < solid.max_x
                    && p.z + crate::movement::RADIUS > solid.min_z
                    && p.z - crate::movement::RADIUS < solid.max_z
                    && p.y - PLAYER_FLOOR_Y < solid.top
                    && p.y - PLAYER_FLOOR_Y + crate::combat::body_height(p.campaign, p.ducking)
                        > solid.bottom
            }) || self.vehicles.iter().any(|v| {
                v.state.hp > 0
                    && (v.state.driver.is_some() || v.state.gunner.is_some())
                    && crate::maps::walker_solids_overlap(solid, crate::vehicles::hull(&v.state))
            }) {
                return;
            }
        }
        self.map = world;
        self.walker = None;
        let run = self.mission.as_mut().unwrap();
        run.m14.as_mut().unwrap().machine_fallen = true;
        run.changed_at = self.tick;
    }
    pub(super) fn advance_m14(&mut self) {
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
        let Some(g) = self.map.m14_geometry() else {
            return;
        };
        let jeep_alive = self
            .vehicles
            .iter()
            .any(|v| v.state.id == 1 && v.state.hp > 0);
        let occupied = self
            .players
            .iter()
            .any(|p| p.is_participant() && self.vehicle_seat(p.id).is_some());
        let phase = self.walker.as_ref().map(|w| w.state.phase);
        let hp = self.walker.as_ref().map(|w| w.state.hp);
        let pad_clear = self.encounters.is_complete(3);
        let support_clear = self.encounters.is_complete(4);
        let old = self.m14_mission_state().unwrap().m14.unwrap();
        let p = self.mission.as_mut().unwrap().m14.as_mut().unwrap();
        if !p.challenges.walker_disabled {
            p.challenges.jeep_preserved &= jeep_alive;
            if phase.is_some_and(|phase| phase != WalkerPhase::Dormant) {
                p.challenges.on_foot &= !occupied;
            }
        }
        if phase == Some(WalkerPhase::Recovery) && p.first_recovery_until.is_none() {
            p.first_recovery_until = self.walker.as_ref().map(|w| w.state.phase_ends);
        }
        p.first_cycle_complete |= p.first_recovery_until.is_some_and(|end| self.tick >= end);
        p.challenges.walker_disabled |= hp == Some(0);
        if p.support_stage == 0
            && (p.first_cycle_complete || p.challenges.walker_disabled)
            && hp.is_some_and(|hp| hp <= 600)
        {
            p.support_stage = 1;
        }
        let stage_three = p.support_stage == 1
            && pad_clear
            && (p.challenges.walker_disabled || hp.is_some_and(|hp| hp <= 300));
        if stage_three {
            p.support_stage = 2;
        }
        if stage_three {
            self.request_walker_station(2);
        }
        if hp == Some(0) {
            self.try_m14_fall();
        }
        let index = self.mission.as_ref().unwrap().m14.as_ref().unwrap().index;
        let arrived = |action: &MissionObjectiveAction| matches!(action,MissionObjectiveAction::Arrival{region,..} if self.players.iter().any(|a|a.is_participant()&&self.contact_eligible(a)&&region.contains([a.x,a.y-PLAYER_FLOOR_Y,a.z])));
        let satisfied = match index {
            0 => arrived(&g.objectives[0].action),
            1..=3 => self.encounters.is_complete(index - 1),
            4 => {
                self.mission
                    .as_ref()
                    .unwrap()
                    .m14
                    .as_ref()
                    .unwrap()
                    .machine_fallen
                    && pad_clear
                    && support_clear
            }
            5 => self.encounters.is_complete(5),
            _ => false,
        };
        if satisfied {
            let p = self.mission.as_mut().unwrap().m14.as_mut().unwrap();
            p.index += 1;
            p.challenges.depot_secured = p.index >= 2;
        }
        let new = self.m14_mission_state().unwrap();
        if new.m14.as_ref() != Some(&old) {
            self.mission.as_mut().unwrap().changed_at = self.tick;
        }
        // Require a new Use after the final group has become a completed objective.
        if satisfied || !new.prompts.iter().any(|p| requests.contains(&p.player_id)) {
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
