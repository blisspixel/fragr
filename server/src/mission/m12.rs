//! Terms of Cooperation ordered clear, shelter, pump and real aid facts.
use super::*;
use crate::movement::{Arena, Solid};
use crate::protocol::{
    M12ChallengeState, M12ObjectiveState, MissionObjective, MissionObjectiveAction,
    M12_OBJECTIVE_IDS,
};

#[derive(Default)]
pub(super) struct M12Progress {
    pub(super) index: usize,
    pub(super) challenges: M12ChallengeState,
    pub(super) aid_vehicle_ids: Vec<u32>,
    pub(super) blast_floor: u32,
    pub(super) seen_blasts: std::collections::VecDeque<u32>,
    pub(super) wreck_serial: Option<u32>,
}
const OBJECTIVES: usize = M12_OBJECTIVE_IDS.len();
#[cfg(test)]
mod tests;
impl GameState {
    fn m12_source_active(&self, source: Uuid) -> bool {
        self.mission
            .as_ref()
            .is_some_and(|r| r.m12.is_some() && r.phase == MissionPhase::InProgress)
            && !self.campaign_run_frozen()
            && self
                .players
                .iter()
                .any(|p| p.id == source && actor_active(self.mission.as_ref(), p.id, p.campaign))
    }
    fn apply_m12_pump_damage(&mut self, index: usize, damage: i32) {
        if damage <= 0 {
            return;
        }
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let Some(p) = run.m12.as_mut() else {
            return;
        };
        let old = p.challenges.pump_health[index];
        let next = old.saturating_sub(u16::try_from(damage).unwrap_or(u16::MAX));
        if old != next {
            p.challenges.pump_health[index] = next;
            p.challenges.first_pump_damage_at.get_or_insert(self.tick);
            run.changed_at = self.tick;
        }
    }
    pub(crate) fn damage_m12_pump(
        &mut self,
        shooter: Uuid,
        solid: usize,
        end: [f32; 3],
        normal: [f32; 3],
        damage: i32,
    ) {
        if damage <= 0 || !self.m12_source_active(shooter) {
            return;
        }
        let Some(g) = self.map.m12_geometry() else {
            return;
        };
        let Some(index) = g.pumps.iter().position(|p| p.solids.contains(&solid)) else {
            return;
        };
        let Some(host) = self.map.arena().solids.get(solid) else {
            return;
        };
        let min = [host.min_x, host.bottom, host.min_z];
        let max = [host.max_x, host.top, host.max_z];
        if (0..3).any(|i| {
            !end[i].is_finite()
                || !normal[i].is_finite()
                || end[i] < min[i] - 0.001
                || end[i] > max[i] + 0.001
        }) || !(0..3).any(|i| {
            (normal[i].abs() - 1.0).abs() < 0.001
                && (0..3).filter(|j| *j != i).all(|j| normal[j].abs() < 0.001)
                && (end[i] - if normal[i] < 0.0 { min[i] } else { max[i] }).abs() < 0.001
        }) {
            return;
        }
        self.apply_m12_pump_damage(index, damage);
    }
    /// Root calls this only for a resolved non-wreck blast. A committed canister's dead source remains valid.
    pub(crate) fn note_m12_blast(
        &mut self,
        serial: u32,
        source: Uuid,
        position: [f32; 3],
        radius: f32,
        peak: f32,
        arena: &Arena,
    ) {
        if !self.m12_source_active(source)
            || !position.iter().all(|v| v.is_finite())
            || !radius.is_finite()
            || radius <= 0.0
            || !peak.is_finite()
            || peak <= 0.0
        {
            return;
        }
        let Some(g) = self.map.m12_geometry() else {
            return;
        };
        let Some(p) = self.mission.as_mut().and_then(|r| r.m12.as_mut()) else {
            return;
        };
        if serial <= p.blast_floor || p.seen_blasts.contains(&serial) {
            return;
        }
        // The resolver owns unique serials. Retain a bounded overlap window for active projectiles and duplicate ingress.
        if p.seen_blasts.len() == 512 {
            p.seen_blasts.pop_front();
        }
        p.seen_blasts.push_back(serial);
        let damage: [i32; 2] = std::array::from_fn(|index| {
            g.pumps[index]
                .solids
                .iter()
                .filter_map(|host| {
                    let s = arena.solids.get(*host)?;
                    let point = [
                        position[0].clamp(s.min_x, s.max_x),
                        position[1].clamp(s.bottom, s.top),
                        position[2].clamp(s.min_z, s.max_z),
                    ];
                    let distance = (0..3)
                        .map(|i| (position[i] - point[i]).powi(2))
                        .sum::<f32>()
                        .sqrt();
                    let value = (peak * (1.0 - distance / radius)).floor() as i32;
                    if value <= 0 {
                        return None;
                    }
                    // Only this exact registered host is excluded. Other pump parts and every unrelated wall still cover.
                    let cover: Vec<_> = arena
                        .solids
                        .iter()
                        .enumerate()
                        .filter(|(i, _)| i != host)
                        .map(|(_, s)| *s)
                        .collect();
                    crate::combat::line_of_sight(position, point, &cover).then_some(value)
                })
                .max()
                .unwrap_or(0)
        });
        for (index, damage) in damage.into_iter().enumerate() {
            self.apply_m12_pump_damage(index, damage);
        }
    }
    pub(crate) fn note_m12_assessor_wreck(
        &mut self,
        owner: Uuid,
        serial: u32,
        killed_ids: &[Uuid],
    ) {
        if !self.m12_source_active(owner)
            || !self.encounters.registered_in_group(owner, 2)
            || !self
                .players
                .iter()
                .any(|p| p.id == owner && p.hp <= 0 && crate::combat::is_assessor(p.campaign))
        {
            return;
        }
        let kills = killed_ids
            .iter()
            .copied()
            .collect::<HashSet<_>>()
            .into_iter()
            .filter(|id| {
                *id != owner
                    && self.encounters.registered_in_group(*id, 2)
                    && self.players.iter().any(|p| {
                        p.id == *id
                            && p.hp <= 0
                            && matches!(
                                p.campaign,
                                Some(CampaignActor::Union {
                                    kind: crate::protocol::EnemyKind::Clerk,
                                    ..
                                })
                            )
                    })
            })
            .count();
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let Some(p) = run.m12.as_mut() else {
            return;
        };
        if serial <= p.blast_floor || p.wreck_serial.is_some() {
            return;
        }
        p.wreck_serial = Some(serial);
        p.challenges.assessor_wreck_union_kills = u8::try_from(kills).unwrap_or(3).min(3);
        run.changed_at = self.tick;
    }
    pub(super) fn m12_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m12.as_ref()?;
        let g = &run.initial_map.m12_objectives()?.geometry;
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
        let mut completed: Vec<_> = g
            .objectives
            .iter()
            .take(p.index.min(OBJECTIVES))
            .map(|o| o.id.clone())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = if departed {
            None
        } else if p.index < OBJECTIVES {
            Some(g.objectives[p.index].clone())
        } else {
            Some(MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: g.departure.clone(),
                },
            })
        };
        let all_aboard = p.index == OBJECTIVES
            && !party.is_empty()
            && party.iter().all(|m| m.ready && m.alive && m.aboard);
        let arena = self.current_arena();
        let prompts = if run.phase == MissionPhase::InProgress && !self.campaign_run_frozen() {
            self.players
                .iter()
                .filter(|a| {
                    a.is_participant()
                        && a.hp > 0
                        && a.respawn_timer.is_none()
                        && run.ready.contains(&a.id)
                })
                .filter(|a| {
                    all_aboard && can_use_in_arena(a, &g.departure, &self.map, &arena)
                        || p.index == 5 && can_use_in_arena(a, &g.commitment, &self.map, &arena)
                        || p.index >= 4
                            && !p.challenges.shelter_opened
                            && can_use_in_arena(a, &g.shelter_release, &self.map, &arena)
                        || p.index >= 3
                            && !p.challenges.workers_released
                            && can_use_in_arena(a, &g.worker_release, &self.map, &arena)
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
            id: MissionId::TermsOfCooperation,
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
            m12: Some(M12ObjectiveState {
                completed,
                current,
                challenges: p.challenges.clone(),
                aid_vehicle_ids: p.aid_vehicle_ids.clone(),
            }),
        })
    }
    /// Materialize prepared aid jeeps atomically, only when their parked footprints are currently empty.
    fn arrive_m12_aid(&mut self) -> Option<Vec<u32>> {
        let g = self.map.m12_geometry()?;
        if self.vehicles.len() + 2 > crate::protocol::MAX_VEHICLES
            || self.vehicles.iter().map(|v| v.state.id).max().unwrap_or(0) > u32::MAX - 2
        {
            return None;
        }
        let arena = self.current_arena();
        let hulls: Vec<Solid> = g
            .aid_vehicles
            .iter()
            .map(|v| crate::vehicles::hull(&crate::vehicles::Jeep::new(1, v.feet, v.yaw).state))
            .collect();
        if g.aid_vehicles
            .iter()
            .any(|v| !crate::vehicles::clear_body(v.feet, v.yaw, &arena))
            || hulls.iter().any(|h| {
                self.players
                    .iter()
                    .filter(|p| self.contact_eligible(p))
                    .any(|p| {
                        p.x + crate::movement::RADIUS > h.min_x
                            && p.x - crate::movement::RADIUS < h.max_x
                            && p.z + crate::movement::RADIUS > h.min_z
                            && p.z - crate::movement::RADIUS < h.max_z
                            && p.y - PLAYER_FLOOR_Y
                                + crate::combat::body_height(p.campaign, p.ducking)
                                > h.bottom
                            && p.y - PLAYER_FLOOR_Y < h.top
                    })
            })
        {
            return None;
        }
        drop(arena);
        let first = self.add_jeep(g.aid_vehicles[0].feet, g.aid_vehicles[0].yaw)?;
        let Some(second) = self.add_jeep(g.aid_vehicles[1].feet, g.aid_vehicles[1].yaw) else {
            self.vehicles.retain(|v| v.state.id != first);
            return None;
        };
        for supply in &mut self.pickups {
            if self.map.is_m12_aid_supply(&supply.id) {
                supply.available = true;
            }
        }
        Some(vec![first, second])
    }
    pub(super) fn advance_m12(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
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
        let Some(p) = run.m12.as_ref() else {
            return;
        };
        let Some(prepared) = run.initial_map.m12_objectives() else {
            return;
        };
        let g = &prepared.geometry;
        let index = p.index;
        let arrived = |action: &MissionObjectiveAction| matches!(action,MissionObjectiveAction::Arrival {region,..} if self.players.iter().any(|a|a.is_participant()&&a.hp>0&&a.respawn_timer.is_none()&&run.ready.contains(&a.id)&&region.contains([a.x,a.y-PLAYER_FLOOR_Y,a.z])));
        let group = self.map.m12_encounter_index(index);
        let arc_owned = self.players.iter().any(|a| {
            a.is_participant()
                && a.hp > 0
                && run.ready.contains(&a.id)
                && a.inventory.owns(crate::protocol::WeaponType::Arc)
        });
        let passed = index < 3 && self.encounters.is_awake(index + 1);
        if index < 5
            && group.is_some_and(|g| self.encounters.is_complete(g))
            && (arrived(&g.objectives[index].action) || passed)
            && (index != 1 || arc_owned)
        {
            let aid = if index == 4 {
                let Some(ids) = self.arrive_m12_aid() else {
                    return;
                };
                Some(ids)
            } else {
                None
            };
            let run = self.mission.as_mut().unwrap();
            let p = run.m12.as_mut().unwrap();
            p.index += 1;
            if index == 3 {
                p.challenges.shelter_route_secured_at = Some(self.tick);
            }
            if let Some(ids) = aid {
                p.aid_vehicle_ids = ids;
            }
            run.changed_at = self.tick;
            return;
        }
        let arena = self.current_arena();
        let used = |target: &UseTarget| {
            self.players.iter().any(|a| {
                requests.contains(&a.id)
                    && a.is_participant()
                    && a.hp > 0
                    && a.respawn_timer.is_none()
                    && run.ready.contains(&a.id)
                    && can_use_in_arena(a, target, &self.map, &arena)
            })
        };
        let shelter = index >= 4 && !p.challenges.shelter_opened && used(&g.shelter_release);
        let workers = index >= 3 && !p.challenges.workers_released && used(&g.worker_release);
        let commitment = index == 5 && used(&g.commitment);
        if shelter || workers || commitment {
            let opened = if shelter {
                self.map.prepared_m12_world()
            } else {
                None
            };
            if shelter && opened.is_none() {
                return;
            }
            drop(arena);
            if let Some(map) = opened {
                self.map = map;
            }
            let run = self.mission.as_mut().unwrap();
            let p = run.m12.as_mut().unwrap();
            p.challenges.shelter_opened |= shelter;
            p.challenges.workers_released |= workers;
            if commitment {
                p.index += 1;
            }
            run.changed_at = self.tick;
            return;
        }
        let all_aboard = index == OBJECTIVES
            && !self.m12_mission_state().unwrap().party.is_empty()
            && self
                .m12_mission_state()
                .unwrap()
                .party
                .iter()
                .all(|m| m.ready && m.alive && m.aboard);
        if !all_aboard || !used(&g.departure) {
            return;
        }
        let exit = if run.solo.is_some() {
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
        drop(arena);
        let run = self.mission.as_mut().unwrap();
        run.phase = MissionPhase::Departed;
        run.changed_at = self.tick;
        if let Some(solo) = run.solo.as_mut() {
            if let Some(exit) = exit {
                solo.capture_exit(exit);
            }
            solo.state.status = crate::protocol::CampaignRunStatus::Complete;
        }
    }
}
