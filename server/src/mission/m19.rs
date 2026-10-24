//! Planned Works: take a jetpack, cross the concourse, learn the Paver on
//! the tram street, break the market strips, reach the tanks, run the roof
//! loop and get through the marked trench to the waterworks.
use super::*;
use crate::protocol::{
    InteractionKind, InteractionPrompt, M19ChallengeState, M19ObjectiveState, MissionMember,
    MissionObjectiveAction, MissionPhase, M19_OBJECTIVE_IDS,
};
use crate::sim::PLAYER_FLOOR_Y;
use std::collections::HashSet;

/// Encounter groups, in authored order.
const CROSSING: usize = 0;
const STREET: usize = 1;
const MARKET: usize = 2;
const ROOFS: usize = 3;

pub(crate) struct M19Progress {
    pub(super) index: usize,
    pub(super) challenges: M19ChallengeState,
    /// `GameState::paver_strip_hits` when this attempt began.
    strip_hits_at_entry: u64,
}

impl M19Progress {
    pub(super) fn new(strip_hits: u64) -> Self {
        Self {
            index: 0,
            challenges: M19ChallengeState::default(),
            strip_hits_at_entry: strip_hits,
        }
    }
}

#[cfg(test)]
mod route_tests;
#[cfg(test)]
mod tests;

impl GameState {
    /// Later groups are placed, dormant, before the party can see their
    /// ground. Nothing ahead of the tanks hovers in view of an earlier fight.
    pub(crate) fn m19_encounter_available(&self, index: usize) -> bool {
        let Some(p) = self.mission.as_ref().and_then(|r| r.m19.as_ref()) else {
            return true;
        };
        match index {
            CROSSING => true,
            STREET | MARKET => p.index >= 2,
            ROOFS => p.index >= 5,
            // The trench crew appears only once the roof watch is down, so a
            // party clearing the workshop never meets the trench first.
            _ => p.index >= 7,
        }
    }

    fn m19_prompts(
        &self,
        target: &crate::protocol::UseTarget,
        run: &MissionRun,
        arena: &crate::movement::Arena,
    ) -> Vec<InteractionPrompt> {
        self.players
            .iter()
            .filter(|a| {
                a.is_participant()
                    && self.contact_eligible(a)
                    && run.ready.contains(&a.id)
                    && can_use_in_arena(a, target, &self.map, arena)
            })
            .map(|a| InteractionPrompt {
                player_id: a.id,
                kind: InteractionKind::ObjectiveUse,
            })
            .collect()
    }

    pub fn m19_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m19.as_ref()?;
        let g = run.initial_map.m19_geometry()?;
        let departed = run.phase == MissionPhase::Departed;
        let party: Vec<_> = self
            .players
            .iter()
            .filter(|pl| pl.is_participant())
            .map(|a| {
                let ready = run.ready.contains(&a.id);
                let alive = a.hp > 0 && a.respawn_timer.is_none();
                MissionMember {
                    id: a.id,
                    name: a.name.clone(),
                    ready,
                    alive,
                    aboard: run.phase != MissionPhase::Briefing
                        && ready
                        && alive
                        && self.contact_eligible(a)
                        && g.boarding.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z]),
                }
            })
            .collect();
        let mut completed: Vec<_> = M19_OBJECTIVE_IDS
            .iter()
            .take(p.index)
            .map(|id| (*id).to_owned())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = if departed {
            None
        } else if p.index < M19_OBJECTIVE_IDS.len() {
            Some(g.objectives[p.index].clone())
        } else {
            Some(g.departure_objective())
        };
        let arena = self.current_arena();
        let mut prompts = Vec::new();
        if run.phase == MissionPhase::InProgress && !self.campaign_run_frozen() {
            if p.index == 0 {
                prompts = self.m19_prompts(&g.stores, run, &arena);
            } else if p.index == M19_OBJECTIVE_IDS.len()
                && !party.is_empty()
                && party.iter().all(|m| m.ready && m.alive && m.aboard)
            {
                prompts = self.m19_prompts(&g.departure, run, &arena);
            }
        }
        Some(MissionState {
            id: MissionId::PlannedWorks,
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
            m18: None,
            m19: Some(M19ObjectiveState {
                completed,
                current,
                challenges: p.challenges.clone(),
                jetpack_taken: p.index >= 1,
                latch_departed: p.index >= 6,
                gate_open: p.index >= 8,
                brief_completed: p.challenges.brief_completed(run.rules.difficulty),
            }),
        })
    }

    /// A participant inside the current arrival objective's region.
    fn m19_arrived(&self, objective: &crate::protocol::MissionObjective) -> bool {
        let MissionObjectiveAction::Arrival { region, .. } = &objective.action else {
            return false;
        };
        self.players.iter().any(|a| {
            a.is_participant()
                && self.contact_eligible(a)
                && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
        })
    }

    pub(super) fn advance_m19(&mut self) {
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
        let Some(g) = self.map.m19_geometry() else {
            return;
        };
        let old = self.m19_mission_state().unwrap().m19.unwrap();
        let index = self.mission.as_ref().unwrap().m19.as_ref().unwrap().index;

        // Combat receipts are monotone within the attempt.
        let interrupted = self.encounters.paver_interruptions() > 0;
        let strip_hits = self.paver_strip_hits;
        {
            let p = self.mission.as_mut().unwrap().m19.as_mut().unwrap();
            p.challenges.paver_interrupted |= interrupted;
            p.challenges.strip_struck |= strip_hits > p.strip_hits_at_entry;
        }

        let advanced = match index {
            0 => {
                let used = self.players.iter().any(|pl| {
                    requests.contains(&pl.id)
                        && pl.is_participant()
                        && self.contact_eligible(pl)
                        && self
                            .mission
                            .as_ref()
                            .is_some_and(|run| run.ready.contains(&pl.id))
                        && can_use_in_arena(pl, &g.stores, &self.map, self.map.arena())
                });
                used
            }
            1 | 5 | 7 => self.m19_arrived(&g.objectives[index]),
            2..=4 | 6 => {
                let group = match index {
                    2 => CROSSING,
                    3 => STREET,
                    4 => MARKET,
                    _ => ROOFS,
                };
                self.encounters.is_complete(group) && self.m19_arrived(&g.objectives[index])
            }
            _ => false,
        };
        if advanced {
            if index == 7 {
                let Some(world) = self.map.prepared_m19_world(1) else {
                    return;
                };
                self.map = world;
            }
            let p = self.mission.as_mut().unwrap().m19.as_mut().unwrap();
            p.index = index + 1;
            if index == 2 {
                p.challenges.crossing_cleared = true;
            }
            tracing::info!(
                objective = M19_OBJECTIVE_IDS[index],
                "Planned Works objective complete"
            );
        }
        // Coalition gear: once taken, every ready living participant wears a
        // pack, including a late or returning party member.
        if index >= 1 || advanced {
            let ready = self.mission.as_ref().unwrap().ready.clone();
            for player in &mut self.players {
                if player.is_participant()
                    && player.hp > 0
                    && player.jetpack.is_none()
                    && ready.contains(&player.id)
                {
                    player.jetpack = Some(crate::movement::jetpack::Pack {
                        fuel: crate::movement::jetpack::FUEL_MAX,
                    });
                }
            }
        }

        let new = self.m19_mission_state().unwrap();
        if new.m19.as_ref().unwrap() != &old {
            self.mission.as_mut().unwrap().changed_at = self.tick;
        }
        if advanced || index < M19_OBJECTIVE_IDS.len() {
            return;
        }
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
        tracing::info!("Planned Works party departed through the waterworks");
    }
}
