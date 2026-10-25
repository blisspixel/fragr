//! Still Here: the refuge in the first light, then the same refuge years
//! later. Nothing here fights and nothing here can fail. The run's saved
//! survival result is the only way in from a campaign, and this level never
//! writes it: replay cannot spend a continue, change a rescue or replace the
//! run.
use super::*;
use crate::protocol::{
    EpilogueObjectiveState, EpilogueRefuge, MissionObjectiveAction, EPILOGUE_OBJECTIVE_IDS,
    EPILOGUE_TURN_TICKS,
};
use crate::sim::PLAYER_FLOOR_Y;
use std::collections::HashSet;

#[cfg(test)]
mod tests;

#[derive(Debug, Clone, Default)]
pub(crate) struct EpilogueProgress {
    /// Completed ordered objectives: 0, 1 stayed with Latch, 2 walked years later.
    pub(super) index: usize,
    pub(super) turning_at: Option<u64>,
    /// Who the run brought. Kept across a reset; only the entitlement sets it.
    pub(super) refuge: EpilogueRefuge,
}

impl EpilogueProgress {
    pub(crate) fn new(refuge: EpilogueRefuge) -> Self {
        Self {
            refuge,
            ..Self::default()
        }
    }
}

/// The people a completed run carried, read from its saved receipts. Presence
/// only: an absent rescue never confirms a death and never gates the walk.
pub(crate) fn refuge_from(document: &run_file::RunDocument) -> EpilogueRefuge {
    EpilogueRefuge {
        cars: document
            .m03_outcome
            .as_ref()
            .is_some_and(|yard| !yard.liberated_cars.is_empty()),
        edda: document
            .m04_outcome
            .as_ref()
            .is_some_and(|clinic| !clinic.rescued_patients.is_empty()),
        // Released from the workshop is not the same as getting out: Splice
        // is here only if they reached the freight, as Tern's crew list
        // agrees in level 9.
        splice: document
            .m05_outcome
            .as_ref()
            .is_some_and(|workshop| workshop.evacuated_workers.iter().any(|id| id == "splice")),
        orrin: document
            .m08_outcome
            .as_ref()
            .is_some_and(|archive| archive.recovered_mind_secured),
        sorrel: document
            .m11_outcome
            .as_ref()
            .is_some_and(|tender| tender.transfer_released),
        entrants: document.m15_outcome.as_ref().is_some_and(|stadium| {
            stadium
                .armed_entrants
                .iter()
                .any(|entrant| !stadium.fallen_entrants.contains(entrant))
        }),
        bus: document
            .m16_outcome
            .as_ref()
            .is_some_and(|avenue| avenue.bus_freed),
    }
}

impl GameState {
    /// The campaign's terminal survival opens the epilogue read-only. Any
    /// other saved step, including a run still inside the wipe, is refused.
    pub(crate) fn load_epilogue_entitlement(
        &mut self,
        document: &run_file::RunDocument,
        content_sha256: [u8; 32],
    ) -> Result<(), &'static str> {
        if self.tick != 0 || !self.players.is_empty() {
            return Err("the epilogue entitlement must be read before admission");
        }
        document.validate(content_sha256)?;
        if !document.survived_the_wipe() {
            return Err("only a recorded survival of Local Exception opens Still Here");
        }
        let refuge = refuge_from(document);
        let run = self
            .mission
            .as_mut()
            .ok_or("Still Here requires its mission")?;
        let progress = run.epilogue.as_mut().ok_or("this map is not Still Here")?;
        progress.refuge = refuge;
        run.rules = document.rules;
        tracing::info!(?refuge, "Still Here opened by the run's survival");
        Ok(())
    }

    pub(crate) fn epilogue_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.epilogue.as_ref()?;
        let g = self.map.epilogue_geometry()?;
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
                    aboard: ready
                        && alive
                        && run.phase != MissionPhase::Briefing
                        && g.later
                        && g.arrival.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z]),
                }
            })
            .collect();
        let departed = run.phase == MissionPhase::Departed;
        let mut completed: Vec<String> = EPILOGUE_OBJECTIVE_IDS
            .iter()
            .take(p.index)
            .map(|id| (*id).to_owned())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = match p.index {
            _ if departed => None,
            0 => Some(g.latch_objective()),
            1 => Some(g.arrival_objective()),
            _ => Some(g.departure_objective()),
        };
        let target = match p.index {
            0 => Some(&g.latch),
            2 if g.later => Some(&g.departure),
            _ => None,
        };
        let mut prompts = Vec::new();
        if let Some(target) = target.filter(|_| run.phase == MissionPhase::InProgress) {
            let arena = self.current_arena();
            prompts.extend(
                self.players
                    .iter()
                    .filter(|a| {
                        self.contact_eligible(a)
                            && run.ready.contains(&a.id)
                            && can_use_in_arena(a, target, &self.map, &arena)
                    })
                    .map(|a| InteractionPrompt {
                        player_id: a.id,
                        kind: InteractionKind::ObjectiveUse,
                    }),
            );
        }
        Some(MissionState {
            id: MissionId::StillHere,
            run: None,
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            m20: None,
            epilogue: Some(EpilogueObjectiveState {
                completed,
                current,
                refuge: p.refuge,
                turning_at: p.turning_at,
                later: g.later,
                blocking: g.blocking(&p.refuge),
            }),
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
            m19: None,
        })
    }

    /// Everyone standing in the current world blocks a walker, as a person
    /// would. Their feet are authored clear of both walks.
    pub(super) fn append_epilogue_contacts(
        &self,
        bodies: &mut Vec<crate::movement::contact::ContactBody>,
    ) {
        let Some(p) = self.mission.as_ref().and_then(|r| r.epilogue.as_ref()) else {
            return;
        };
        let Some(g) = self.map.epilogue_geometry() else {
            return;
        };
        for person in g.blocking(&p.refuge) {
            bodies.push(crate::sim::contact::civilian(
                format!("epilogue/{}", person.id),
                person.feet,
            ));
        }
    }

    /// The world turns: the same refuge years later, the party standing at
    /// the tram stop. A new body baseline, because no step walks between them.
    fn turn_epilogue_world(&mut self) {
        let Some(world) = self.map.prepared_epilogue_world(1) else {
            return;
        };
        let Some(g) = world.epilogue_geometry() else {
            return;
        };
        self.map = world;
        let ready: HashSet<Uuid> = self
            .mission
            .as_ref()
            .map(|run| run.ready.clone())
            .unwrap_or_default();
        // Side by side on the platform, never on one spot.
        let slots = g.later_slots();
        for (player, feet) in self
            .players
            .iter_mut()
            .filter(|p| p.is_participant() && ready.contains(&p.id))
            .zip(slots)
        {
            player.x = feet[0];
            player.z = feet[2];
            player.y = feet[1] + PLAYER_FLOOR_Y;
            player.yaw = g.later_yaw;
            player.pitch = 0.0;
            player.vy = 0.0;
            player.reset_movement_baseline();
            player.clear_input();
        }
        tracing::info!("Still Here: years later");
    }

    fn epilogue_in_region(&self, region: &crate::protocol::Region3) -> bool {
        let Some(run) = self.mission.as_ref() else {
            return false;
        };
        self.players.iter().any(|a| {
            a.is_participant()
                && self.contact_eligible(a)
                && run.ready.contains(&a.id)
                && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
        })
    }

    pub(super) fn advance_epilogue(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        if !self
            .mission
            .as_ref()
            .is_some_and(|r| r.phase == MissionPhase::InProgress)
        {
            return;
        }
        let Some(before) = self.epilogue_mission_state() else {
            return;
        };
        let used = before
            .prompts
            .iter()
            .any(|p| requests.contains(&p.player_id));
        let old = before.epilogue;
        let tick = self.tick;
        let (index, turning_at) = {
            let p = self.mission.as_ref().unwrap().epilogue.as_ref().unwrap();
            (p.index, p.turning_at)
        };
        match index {
            0 if used => {
                let p = self.mission.as_mut().unwrap().epilogue.as_mut().unwrap();
                p.index = 1;
                p.turning_at = Some(tick);
                tracing::info!("Still Here: stayed with Latch while they counted");
            }
            1 => {
                let due = turning_at.is_some_and(|at| tick >= at + EPILOGUE_TURN_TICKS);
                if due && self.map.epilogue_stage() == 0 {
                    self.turn_epilogue_world();
                } else if self.map.epilogue_stage() == 1 {
                    let arrived = self
                        .map
                        .epilogue_geometry()
                        .and_then(|g| match g.arrival_objective().action {
                            MissionObjectiveAction::Arrival { region, .. } => Some(region),
                            _ => None,
                        })
                        .is_some_and(|region| self.epilogue_in_region(&region));
                    if arrived {
                        self.mission
                            .as_mut()
                            .unwrap()
                            .epilogue
                            .as_mut()
                            .unwrap()
                            .index = 2;
                        tracing::info!("Still Here: the court years later");
                    }
                }
            }
            2 if used => {
                let run = self.mission.as_mut().unwrap();
                run.phase = MissionPhase::Departed;
                run.changed_at = tick;
                tracing::info!("Still Here: Latch, asked the score, stopped counting");
            }
            _ => {}
        }
        let new = self.epilogue_mission_state().and_then(|s| s.epilogue);
        if new != old {
            self.mission.as_mut().unwrap().changed_at = self.tick;
        }
    }
}
