//! Passenger Manifest uses supported walking routes, never waypoint teleportation.
use super::*;
use crate::movement::{integrate, Arena, MoveState, BODY_HEIGHT, CONTACT_EPSILON, DT_LIVE, RADIUS};
use crate::protocol::{
    M09CrewState, M09MapGeometry, M09ObjectiveState, MissionObjectiveAction, M09_OBJECTIVE_IDS,
};

pub(super) struct M09Progress {
    pub(super) index: usize,
    pub(super) crew: Vec<M09CrewState>,
    pub(super) route_points: Vec<usize>,
    pub(super) charge_falls: u8,
}

impl M09Progress {
    pub(super) fn new(g: &M09MapGeometry, edda_present: bool, splice_present: bool) -> Self {
        let crew: Vec<_> = g
            .crew
            .iter()
            .filter(|c| (c.id != "edda" || edda_present) && (c.id != "splice" || splice_present))
            .map(|c| M09CrewState {
                id: c.id.clone(),
                feet: c.route[0],
                aboard: false,
            })
            .collect();
        Self {
            index: 0,
            route_points: vec![1; crew.len()],
            crew,
            charge_falls: 0,
        }
    }
}

impl GameState {
    pub(crate) fn ensure_m09_companion(&mut self) {
        if self
            .mission
            .as_ref()
            .is_some_and(|r| r.m09.is_some() && r.phase == MissionPhase::InProgress)
        {
            if let Some(g) = self.map.m09_geometry() {
                self.spawn_campaign_companion(g.companion_start, false);
            }
        }
    }

    pub(crate) fn m09_encounter_available(&self, index: usize) -> bool {
        self.mission
            .as_ref()
            .and_then(|r| r.m09.as_ref())
            .is_none_or(|p| index < 3 || p.index >= 3)
    }

    /// Called only after an actual committed supported charge owns a lethal descent.
    pub(crate) fn note_m09_charge_fall(&mut self) {
        if self.campaign_run_frozen() {
            return;
        }
        if let Some(run) = self
            .mission
            .as_mut()
            .filter(|r| r.phase == MissionPhase::InProgress)
        {
            if let Some(p) = &mut run.m09 {
                p.charge_falls = p.charge_falls.saturating_add(1).min(7);
                run.changed_at = self.tick;
            }
        }
    }

    pub(super) fn m09_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m09.as_ref()?;
        let g = self.map.m09_geometry()?;
        let departed = run.phase == MissionPhase::Departed;
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
        let use_target = if p.index == 2 && self.encounters.is_complete(2) {
            Some(&g.crew_release)
        } else if p.index == 8
            && !party.is_empty()
            && party.iter().all(|m| m.ready && m.alive && m.aboard)
        {
            Some(&g.departure)
        } else {
            None
        };
        let prompts = if run.phase == MissionPhase::InProgress && !self.campaign_run_frozen() {
            use_target.map_or_else(Vec::new, |target| {
                self.players
                    .iter()
                    .filter(|p| {
                        p.is_participant()
                            && p.hp > 0
                            && p.respawn_timer.is_none()
                            && run.ready.contains(&p.id)
                            && can_use(p, target, &self.map)
                    })
                    .map(|p| InteractionPrompt {
                        player_id: p.id,
                        kind: InteractionKind::ObjectiveUse,
                    })
                    .collect()
            })
        } else {
            Vec::new()
        };
        let mut completed: Vec<_> = M09_OBJECTIVE_IDS
            .iter()
            .take(p.index)
            .map(|id| (*id).to_owned())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        Some(MissionState {
            id: MissionId::PassengerManifest,
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
            m09: Some(M09ObjectiveState {
                completed,
                current: if departed { None } else { g.step(p.index) },
                crew_released: p.index >= 3,
                crew: p.crew.clone(),
                hatch_open: g.hatch_open,
                charge_falls: p.charge_falls,
                carried_archive: run.solo.as_ref().and_then(|s| s.carried_archive.clone()),
            }),
        })
    }

    pub(super) fn advance_m09(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        let Some(state) = self.m09_mission_state() else {
            return;
        };
        if state.phase != MissionPhase::InProgress || self.campaign_run_frozen() {
            return;
        }
        let Some(run) = &self.mission else {
            return;
        };
        let Some(p) = &run.m09 else {
            return;
        };
        let Some(g) = self.map.m09_geometry() else {
            return;
        };
        let index = p.index;
        let used = state
            .prompts
            .iter()
            .any(|p| requests.contains(&p.player_id));
        let advance = if index == 2 {
            used
        } else if index < 8 {
            let Some(step) = g.step(index) else {
                return;
            };
            self.encounters.is_complete(index)
                && matches!(step.action,MissionObjectiveAction::Arrival {region,..}
                if self.players.iter().any(|p|p.is_participant() && p.hp>0 && p.respawn_timer.is_none()
                    && run.ready.contains(&p.id) && region.contains([p.x,p.y-PLAYER_FLOOR_Y,p.z])))
        } else {
            false
        };
        if advance {
            // The gallery's cleared clamp control opens the one hatch. Select a
            // prepared world; the shared tick loop sends MapInfo before facts.
            if index == 6 {
                let Some(opened) = self.map.prepared_m09_world() else {
                    return;
                };
                self.map = opened;
            }
            if let Some(run) = &mut self.mission {
                if let Some(p) = &mut run.m09 {
                    p.index += 1;
                    run.changed_at = self.tick;
                }
            }
            return;
        }
        if index != 8 || !used {
            return;
        }
        let exit = if state.run.is_some() {
            let Some(owner) = run.solo.as_ref().and_then(recovery::SoloRun::owner) else {
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
            if let Some(solo) = &mut run.solo {
                if let Some(exit) = exit {
                    solo.capture_exit(exit);
                }
                solo.state.status = crate::protocol::CampaignRunStatus::Complete;
            }
        }
        tracing::info!("Common Carrier departure confirmed");
    }

    pub(crate) fn advance_m09_crew(&mut self, dt: f32) {
        if !dt.is_finite() || dt <= 0.0 || self.campaign_run_frozen() {
            return;
        }
        let Some(g) = self.map.m09_geometry() else {
            return;
        };
        let arena = self.current_arena().into_owned();
        let mut contacts = self.contact_bodies();
        let Some(run) = self
            .mission
            .as_mut()
            .filter(|r| r.phase == MissionPhase::InProgress)
        else {
            return;
        };
        let Some(p) = run.m09.as_mut().filter(|p| p.index >= 3) else {
            return;
        };
        let dt = dt.min(DT_LIVE);
        for (crew, index) in p.crew.iter_mut().zip(&mut p.route_points) {
            let Some(route) = g.crew.iter().find(|c| c.id == crew.id) else {
                continue;
            };
            let Some(target) = route.route.get(*index) else {
                continue;
            };
            if usize::from(route.held_until[*index]) > p.index {
                continue;
            }
            let dx = target[0] - crew.feet[0];
            let dz = target[2] - crew.feet[2];
            let distance = dx.hypot(dz);
            if distance <= 0.01 && (target[1] - crew.feet[1]).abs() <= 0.01 {
                *index += 1;
                continue;
            }
            let direction = if distance > 0.0 {
                [dx / distance, dz / distance]
            } else {
                [0.0, 0.0]
            };
            let from = MoveState {
                x: crew.feet[0],
                y: crew.feet[1],
                z: crew.feet[2],
                vx: 0.0,
                vz: 0.0,
                vy: 0.0,
                yaw: 0.0,
            };
            let speed = (distance / dt).min(2.0);
            let proposed = integrate(
                MoveState {
                    vx: direction[0] * speed,
                    vz: direction[1] * speed,
                    ..from
                },
                false,
                dt,
                &arena,
            );
            let key = format!("m09/{}", crew.id);
            let moved =
                contact::move_on_route(&key, from, proposed, direction, dt, &arena, &contacts);
            crew.feet = [moved.x, moved.y, moved.z];
            crew.aboard = g.hatch_open && g.boarding.contains(crew.feet);
            if let Some(body) = contacts.iter_mut().find(|c| c.key == key) {
                body.from = moved;
                body.proposed = moved;
            }
            run.changed_at = self.tick;
        }
    }
}

pub(crate) fn m09_route_segment_valid(arena: &Arena, from: [f32; 3], target: [f32; 3]) -> bool {
    if [from, target].iter().any(|p| {
        p.iter().any(|v| !v.is_finite())
            || p[0].abs() > arena.half - RADIUS
            || p[2].abs() > arena.half - RADIUS
            || p[1] < 0.0
            || arena.blocked_body_at(p[0], p[2], p[1], p[1])
            || p[1] + BODY_HEIGHT > crate::movement::MAX_HALF_EXTENT * 2.0
            || [-RADIUS, RADIUS].iter().any(|dx| {
                [-RADIUS, RADIUS].iter().any(|dz| {
                    (arena.support_height(p[0] + dx, p[2] + dz, p[1] + CONTACT_EPSILON) - p[1])
                        .abs()
                        > CONTACT_EPSILON
                })
            })
    }) {
        return false;
    }
    let mut state = MoveState {
        x: from[0],
        y: from[1],
        z: from[2],
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    for _ in 0..1024 {
        let dx = target[0] - state.x;
        let dz = target[2] - state.z;
        let distance = dx.hypot(dz);
        if distance <= 0.01 && (state.y - target[1]).abs() <= 0.01 && state.vy.abs() <= 0.01 {
            return true;
        }
        let speed = (distance / DT_LIVE).min(2.0);
        state.vx = if distance > 0.0 {
            dx / distance * speed
        } else {
            0.0
        };
        state.vz = if distance > 0.0 {
            dz / distance * speed
        } else {
            0.0
        };
        state = integrate(state, false, DT_LIVE, arena);
    }
    false
}
