//! Connected foundry lifecycle, using the same physical gate rules as development maps.
use super::*;
use crate::mission::*;
use crate::protocol::*;
#[derive(Debug)]
pub(in crate::mission) struct M13Progress {
    pub(in crate::mission) index: usize,
    pub(in crate::mission) worker_feet: [[f32; 3]; 3],
    pub(in crate::mission) arrived: [bool; 3],
    pub(in crate::mission) surrendered: bool,
}
impl M13Progress {
    pub(in crate::mission) fn new(g: M13MapGeometry) -> Self {
        Self {
            index: 0,
            worker_feet: g.workers,
            arrived: [false; 3],
            surrendered: false,
        }
    }
}
impl GameState {
    pub(super) fn m13_party_supported(&self, g: &M13MapGeometry) -> bool {
        let Some(run) = self.mission.as_ref() else {
            return false;
        };
        let party: Vec<_> = self.players.iter().filter(|p| p.is_participant()).collect();
        !party.is_empty()
            && party
                .iter()
                .all(|p| run.ready.contains(&p.id) && self.m13_supported(p, g))
    }
    fn m13_supported(&self, player: &Player, g: &M13MapGeometry) -> bool {
        let Some(p) = self.foundry.as_ref() else {
            return false;
        };
        let Some(deck) = lift::deck_at(self.map.arena().solids[g.deck], p.lift_top) else {
            return false;
        };
        self.contact_eligible(player)
            && lift::supported(
                MoveState {
                    x: player.x,
                    y: player.y - PLAYER_FLOOR_Y,
                    z: player.z,
                    vx: 0.0,
                    vz: 0.0,
                    vy: player.vy,
                    yaw: player.yaw,
                },
                deck,
                g.inset_min,
                g.inset_max,
                player.platform_jump_requested(),
            )
    }
    pub(in crate::mission) fn m13_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m13.as_ref()?;
        let gates = self.foundry.as_ref()?;
        let g = run.initial_map.m13_geometry()?;
        let party: Vec<_> = self
            .players
            .iter()
            .filter(|a| a.is_participant())
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
                        && self.m13_supported(a, &g),
                }
            })
            .collect();
        let departed = run.phase == MissionPhase::Departed;
        let mut completed: Vec<_> = M13_OBJECTIVE_IDS
            .iter()
            .take(p.index)
            .map(|id| (*id).into())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = if departed {
            None
        } else if p.index < 7 {
            Some(g.objectives[p.index].clone())
        } else {
            Some(g.departure_objective())
        };
        let all = p.index >= 6
            && gates.lift_phase == lift::Phase::Parked
            && !party.is_empty()
            && party.iter().all(|m| m.ready && m.alive && m.aboard);
        let arena = self.current_arena();
        let prompts = if run.phase == MissionPhase::InProgress && !self.campaign_run_frozen() {
            self.players
                .iter()
                .filter(|a| self.contact_eligible(a) && run.ready.contains(&a.id))
                .filter(|a| {
                    p.surrendered
                        && gates.workers.is_none()
                        && can_use_in_arena(a, &g.release, &self.map, &arena)
                        || all && can_use_in_arena(a, &g.departure, &self.map, &arena)
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
            id: MissionId::WeightOfPermission,
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
            m14: None,
            m15: None,
            m16: None,
            m17: None,
            m18: None,
            m13: Some(M13ObjectiveState {
                completed,
                current,
                challenges: M13ChallengeState {
                    workers: gates.workers,
                    workers_arrived: p.arrived,
                    hazard_hurt: gates.hazard_hurt,
                    supports_cleared: p.index >= 6,
                },
                relay_disabled: gates.relay_disabled,
                overseer_surrendered: p.surrendered,
                worker_feet: p.worker_feet,
                lift: M13LiftState {
                    phase: match gates.lift_phase {
                        lift::Phase::Parked => M13LiftPhase::Parked,
                        lift::Phase::Moving => M13LiftPhase::Moving,
                        lift::Phase::Returning => M13LiftPhase::Returning,
                        lift::Phase::Blocked => M13LiftPhase::Blocked,
                        lift::Phase::Arrived => M13LiftPhase::Arrived,
                    },
                    top: gates.lift_top,
                    tick: self.tick,
                    returning: gates.returning,
                },
                hazard_phase: g.cycle.phase(self.tick),
            }),
        })
    }
    fn move_m13_workers(&mut self, g: &M13MapGeometry) {
        if self.foundry.as_ref().is_none_or(|p| p.workers.is_none()) {
            return;
        }
        for i in 0..2 {
            let Some(p) = self.mission.as_ref().and_then(|r| r.m13.as_ref()) else {
                return;
            };
            if p.arrived[i] {
                continue;
            }
            let feet = p.worker_feet[i];
            let to = g.worker_destinations[i];
            let dx = to[0] - feet[0];
            let dz = to[2] - feet[2];
            let distance = dx.hypot(dz);
            if distance <= 0.04 && (feet[1] - to[1]).abs() < 0.05 {
                let run = self.mission.as_mut().unwrap();
                run.m13.as_mut().unwrap().arrived[i] = true;
                run.changed_at = self.tick;
                continue;
            }
            let direction = [dx / distance.max(0.001), dz / distance.max(0.001)];
            let from = MoveState {
                x: feet[0],
                y: feet[1],
                z: feet[2],
                vx: 0.0,
                vz: 0.0,
                vy: 0.0,
                yaw: 0.0,
            };
            let speed = (distance / 0.05).min(1.2);
            let arena = self.current_arena();
            let proposed = crate::movement::integrate(
                MoveState {
                    vx: direction[0] * speed,
                    vz: direction[1] * speed,
                    ..from
                },
                false,
                0.05,
                &arena,
            );
            let contacts = self.contact_bodies();
            let moved = crate::mission::contact::move_on_route(
                &format!("m13/worker/{i}"),
                from,
                proposed,
                direction,
                0.05,
                &arena,
                &contacts,
            );
            let next = [moved.x, moved.y, moved.z];
            let run = self.mission.as_mut().unwrap();
            run.m13.as_mut().unwrap().worker_feet[i] = next;
            if next != feet {
                run.changed_at = self.tick;
            }
        }
    }
    pub(in crate::mission) fn advance_m13(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|a| std::mem::take(&mut a.interaction_requested).then_some(a.id))
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
        let Some(g) = run.initial_map.m13_geometry() else {
            return;
        };
        if self.encounters.is_complete(2) && !run.m13.as_ref().unwrap().surrendered {
            let run = self.mission.as_mut().unwrap();
            run.m13.as_mut().unwrap().surrendered = true;
            run.changed_at = self.tick;
        }
        self.move_m13_workers(&g);
        let run = self.mission.as_ref().unwrap();
        let p = run.m13.as_ref().unwrap();
        let gates = self.foundry.as_ref().unwrap();
        let index = p.index;
        let eligible = |a: &Player| {
            a.is_participant() && self.contact_eligible(a) && run.ready.contains(&a.id)
        };
        let arrived = |i: usize| match &g.objectives[i].action {
            MissionObjectiveAction::Arrival { region, .. } => self
                .players
                .iter()
                .any(|a| eligible(a) && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])),
            _ => false,
        };
        let passed = match index {
            0 => self.encounters.is_awake(0),
            1 => self.encounters.is_complete(0) && self.encounters.is_complete(1),
            2 => {
                self.encounters.is_complete(2)
                    && self.players.iter().any(|a| {
                        eligible(a)
                            && a.inventory.claimed("office_rocket")
                            && a.inventory.owns(WeaponType::Rocket)
                    })
            }
            3 => self.encounters.is_complete(3) && self.encounters.is_complete(4),
            4 => gates.relay_disabled,
            5 => self.encounters.is_complete(5),
            _ => false,
        };
        if index < 6 && passed && (index != 0 || arrived(0) || self.encounters.is_awake(1)) {
            let run = self.mission.as_mut().unwrap();
            run.m13.as_mut().unwrap().index += 1;
            run.changed_at = self.tick;
            return;
        }
        let arena = self.current_arena();
        let used = |target: &UseTarget| {
            self.players.iter().any(|a| {
                eligible(a)
                    && requests.contains(&a.id)
                    && can_use_in_arena(a, target, &self.map, &arena)
            })
        };
        if p.surrendered && gates.workers.is_none() && used(&g.release) {
            drop(arena);
            self.foundry.as_mut().unwrap().workers = Some(M13_WORKER_RESPONSES);
            self.mission.as_mut().unwrap().changed_at = self.tick;
            return;
        }
        let party: Vec<_> = self.players.iter().filter(|a| a.is_participant()).collect();
        let all = !party.is_empty()
            && party
                .iter()
                .all(|a| eligible(a) && self.m13_supported(a, &g));
        if index >= 6 && all && gates.lift_phase == lift::Phase::Parked && used(&g.departure) {
            drop(arena);
            self.foundry.as_mut().unwrap().lift_phase = lift::Phase::Moving;
            let run = self.mission.as_mut().unwrap();
            run.m13.as_mut().unwrap().index = 7;
            run.changed_at = self.tick;
            return;
        }
        if index != 7 || !all || gates.lift_phase != lift::Phase::Arrived {
            return;
        }
        let exit = if let Some(solo) = &run.solo {
            let Some(owner) = solo.owner() else { return };
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
        drop(arena);
        let run = self.mission.as_mut().unwrap();
        run.phase = MissionPhase::Departed;
        run.changed_at = self.tick;
        if let Some(solo) = run.solo.as_mut() {
            if let Some(entry) = exit {
                solo.capture_exit(entry);
            }
            solo.state.status = CampaignRunStatus::Complete;
        }
    }
}
