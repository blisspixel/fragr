//! Custody archive progression: ordered lessons, the lifted seal, the
//! support-node machine, optional rescue facts and the freight departure.
use super::*;
use crate::protocol::{
    M08ObjectiveState, MissionObjectiveAction, M08_MACHINE_STEP, M08_NODES, M08_NODE_HP,
    M08_OBJECTIVE_IDS,
};

pub(super) struct M08Progress {
    pub(super) index: usize,
    pub(super) node_hp: [u8; M08_NODES],
    pub(super) custody_released: bool,
    pub(super) recovered_mind_secured: bool,
    pub(super) captives_evacuated: bool,
}

impl Default for M08Progress {
    fn default() -> Self {
        Self {
            index: 0,
            node_hp: [M08_NODE_HP; M08_NODES],
            custody_released: false,
            recovered_mind_secured: false,
            captives_evacuated: false,
        }
    }
}

const DEPARTURE_STEP: usize = M08_OBJECTIVE_IDS.len();

impl GameState {
    pub(crate) fn ensure_m08_companion(&mut self) {
        if self
            .mission
            .as_ref()
            .is_some_and(|r| r.m08.is_some() && r.phase == MissionPhase::InProgress)
        {
            if let Some(g) = self.map.m08_geometry() {
                self.spawn_campaign_companion(g.companion_start, false);
            }
        }
    }

    pub(super) fn m08_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m08.as_ref()?;
        let prepared = run.initial_map.m08_objectives()?;
        let g = &prepared.geometry;
        let stage = self.map.m08_stage();
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
        let mut completed: Vec<String> = M08_OBJECTIVE_IDS
            .iter()
            .take(p.index.min(DEPARTURE_STEP))
            .map(|id| (*id).to_string())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = if departed {
            None
        } else {
            g.step(p.index, &p.node_hp)
        };
        let departure_ready = p.index == DEPARTURE_STEP
            && self.encounters.is_complete(prepared.departure_encounter)
            && !party.is_empty()
            && party.iter().all(|m| m.ready && m.alive && m.aboard);
        let prompts = if departure_ready
            && run.phase == MissionPhase::InProgress
            && !self.campaign_run_frozen()
        {
            self.players
                .iter()
                .filter(|p| {
                    p.is_participant()
                        && p.hp > 0
                        && p.respawn_timer.is_none()
                        && run.ready.contains(&p.id)
                        && can_use(p, &g.departure, &self.map)
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
            id: MissionId::CustodianOfRecord,
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
            m09: None,
            m10: None,
            m11: None,
            m12: None,
            m08: Some(M08ObjectiveState {
                completed,
                current,
                node_hp: p.node_hp.to_vec(),
                seal_open: stage >= 1,
                machine_fallen: stage >= 2,
                custodian_joined: p.index >= 2,
                custody_released: p.custody_released,
                recovered_mind_secured: p.recovered_mind_secured,
                transfer_evidence: p.index > 5,
                captives_evacuated: p.captives_evacuated,
            }),
        })
    }

    /// A resolved ray impact on a support node, only while the machine is the
    /// current step. The last node drops the machine into the fallen stage.
    pub(crate) fn damage_m08_node(
        &mut self,
        shooter: Uuid,
        solid: usize,
        end: [f32; 3],
        normal: [f32; 3],
        damage: i32,
    ) {
        let Some(run) = self
            .mission
            .as_ref()
            .filter(|run| run.phase == MissionPhase::InProgress)
        else {
            return;
        };
        let Some(prepared) = run.initial_map.m08_objectives() else {
            return;
        };
        let Some(progress) = run.m08.as_ref() else {
            return;
        };
        let Some(node) = prepared
            .geometry
            .nodes
            .iter()
            .position(|n| n.solid == solid)
        else {
            return;
        };
        if damage <= 0
            || self.campaign_run_frozen()
            || progress.index != M08_MACHINE_STEP
            || progress.node_hp[node] == 0
            || !self.players.iter().any(|p| {
                p.id == shooter && p.is_participant() && actor_active(Some(run), p.id, p.campaign)
            })
        {
            return;
        }
        let host = &self.current_arena().solids[solid];
        let min = [host.min_x, host.bottom, host.min_z];
        let max = [host.max_x, host.top, host.max_z];
        if (0..3).any(|i| !end[i].is_finite() || end[i] < min[i] - 0.001 || end[i] > max[i] + 0.001)
            || !(0..3).any(|i| {
                (normal[i].abs() - 1.0).abs() < 0.001
                    && (0..3).filter(|j| *j != i).all(|j| normal[j].abs() < 0.001)
                    && (end[i] - if normal[i] < 0.0 { min[i] } else { max[i] }).abs() < 0.001
            })
        {
            return;
        }
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let Some(progress) = run.m08.as_mut() else {
            return;
        };
        let left = progress.node_hp[node];
        progress.node_hp[node] = left.saturating_sub(u8::try_from(damage).unwrap_or(u8::MAX));
        run.changed_at = self.tick;
        if progress.node_hp[node] == 0 {
            tracing::info!(node, "Custody support node broken");
        }
        if progress.node_hp.iter().all(|hp| *hp == 0) {
            progress.index += 1;
            if let Some(fallen) = run.initial_map.prepared_m08_world(2) {
                self.map = fallen;
            }
            tracing::info!("Custody machine dropped through the galleries");
        }
    }

    pub(super) fn advance_m08(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        let Some(state) = self.m08_mission_state() else {
            return;
        };
        if state.phase != MissionPhase::InProgress || self.campaign_run_frozen() {
            return;
        }
        let Some(run) = &self.mission else {
            return;
        };
        let Some(prepared) = run.initial_map.m08_objectives() else {
            return;
        };
        let Some(progress) = &run.m08 else {
            return;
        };
        let g = &prepared.geometry;
        // The Auditor's fall lifts the seal and frees the upper bays.
        if self.map.m08_stage() == 0 && self.encounters.is_complete(prepared.seal_encounter) {
            if let Some(opened) = run.initial_map.prepared_m08_world(1) {
                self.map = opened;
                if let Some(run) = &mut self.mission {
                    run.changed_at = self.tick;
                }
                tracing::info!("Upper gallery seal lifted");
            }
            return;
        }
        let arrived = |action: &MissionObjectiveAction| {
            matches!(action, MissionObjectiveAction::Arrival { region, .. }
                if self.players.iter().any(|p| p.is_participant() && p.hp > 0 && p.respawn_timer.is_none()
                    && run.ready.contains(&p.id) && region.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])))
        };
        let seal_cleared = self.encounters.is_complete(prepared.seal_encounter);
        let release = seal_cleared && !progress.custody_released && arrived(&g.bays.action);
        let recover =
            seal_cleared && !progress.recovered_mind_secured && arrived(&g.cabinet.action);
        let step = (progress.index != M08_MACHINE_STEP && progress.index < DEPARTURE_STEP)
            .then(|| g.step(progress.index, &progress.node_hp))
            .flatten();
        // Position of this step's fight in the ordered group list.
        let order = match progress.index {
            0..=3 => Some(progress.index),
            5 => Some(4),
            6 => Some(5),
            _ => None,
        };
        let group = match progress.index {
            0..=3 => Some(prepared.encounters[progress.index]),
            5 => Some(prepared.bridge_encounter),
            6 => Some(prepared.departure_encounter),
            _ => None,
        };
        // A won fight's arrival also counts once the party has clearly moved
        // on, as on the other campaign levels: the next ordered fight woke, or
        // after the last fight someone stands at the freight car.
        let boarding = || {
            self.players.iter().any(|p| {
                p.is_participant()
                    && p.hp > 0
                    && p.respawn_timer.is_none()
                    && run.ready.contains(&p.id)
                    && g.boarding.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z])
            })
        };
        let advance = step.is_some_and(|s| {
            group.is_some_and(|g| self.encounters.is_complete(g))
                && (arrived(&s.action)
                    || order.is_some_and(|o| {
                        super::arrival_passed(&self.encounters, &prepared.encounters, o, boarding)
                    }))
        });
        if release || recover || advance {
            if let Some(run) = &mut self.mission {
                if let Some(progress) = &mut run.m08 {
                    progress.custody_released |= release;
                    progress.recovered_mind_secured |= recover;
                    if advance {
                        progress.index += 1;
                    }
                    run.changed_at = self.tick;
                }
            }
            if release {
                tracing::info!("Lower custody bays released");
            }
            if recover {
                tracing::info!("Recovered mind backup secured");
            }
            return;
        }
        if !state
            .prompts
            .iter()
            .any(|p| requests.contains(&p.player_id))
        {
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
        if let Some(run) = &mut self.mission {
            run.phase = MissionPhase::Departed;
            run.changed_at = self.tick;
            if let Some(progress) = &mut run.m08 {
                // Released captives walk out with the departing party.
                progress.captives_evacuated = progress.custody_released;
                progress.index = DEPARTURE_STEP;
            }
            if let Some(solo) = &mut run.solo {
                if let Some(exit) = exit {
                    solo.capture_exit(exit);
                }
                solo.state.status = crate::protocol::CampaignRunStatus::Complete;
            }
        }
        tracing::info!("Custody freight departure confirmed");
    }
}
